import os
import json
import boto3
from botocore.exceptions import ClientError

USER_POOL_ID = os.environ["USER_POOL_ID"]
HOME_BUCKET = os.environ["HOME_BUCKET"]
TRANSFER_ROLE_ARN = os.environ["TRANSFER_ROLE_ARN"]

cognito = boto3.client("cognito-idp")


def handler(event, context):
    """
    event (例):
    {
      "username": "alice",
      "protocol": "SFTP",
      "sourceIp": "198.51.100.23",
      "serverId": "s-1234567890abcdef0"
    }

    成功時レスポンス (例):
    {
      "Role": "arn:aws:iam::<account-id>:role/transfer-access-role",
      "Policy": "{\"Version\":\"2012-10-17\", ... }",
      "HomeDirectoryType": "LOGICAL",
      "HomeDirectoryDetails": "[{\"Entry\":\"/\",\"Target\":\"/bucket-name/uploads/alice\"}]"
    }

    失敗時は Exception を投げると Transfer Family 側で認証エラー扱いになる。
    """

    print(f"Incoming auth request: {json.dumps(event)}")

    username = event.get("username")
    if not username:
        raise Exception("Missing username")

    # 1. Cognitoユーザー確認
    if not _is_active_cognito_user(username):
        # 存在しない or 有効じゃないユーザは拒否
        print(f"User {username} not allowed")
        raise Exception("Invalid user")

    # 2. ユーザー専用のS3パスを決める
    #    ここでは /uploads/<username>/ を与える
    user_prefix = f"uploads/{username}"

    # 3. Transfer Family 用のIAMポリシー(文字列)を組み立てる
    #    - このユーザには自分のprefix配下だけ触らせたい
    policy_doc = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "AllowListingOfUserFolder",
                "Effect": "Allow",
                "Action": ["s3:ListBucket"],
                "Resource": f"arn:aws:s3:::{HOME_BUCKET}",
                "Condition": {
                    "StringLike": {
                        "s3:prefix": [
                            f"{user_prefix}/*",
                            f"{user_prefix}"
                        ]
                    }
                }
            },
            {
                "Sid": "HomeDirObjectAccess",
                "Effect": "Allow",
                "Action": [
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:PutObjectAcl"
                ],
                "Resource": f"arn:aws:s3:::{HOME_BUCKET}/{user_prefix}/*"
            }
        ]
    }

    # 4. HomeDirectoryDetails:
    #    SFTPクライアントから見ると "/" がホーム。
    #    でも実体は s3://HOME_BUCKET/uploads/<username>
    #    CloudFrontとか関係ない、あくまでTransfer Family用のS3マッピング。
    home_directory_details = [
        {
            "Entry": "/",
            "Target": f"/{HOME_BUCKET}/{user_prefix}"
        }
    ]

    response = {
        "Role": TRANSFER_ROLE_ARN,
        "Policy": json.dumps(policy_doc),
        "HomeDirectoryType": "LOGICAL",
        "HomeDirectoryDetails": json.dumps(home_directory_details)
    }

    print(f"Auth success for {username}: {json.dumps(response)}")
    return response


def _is_active_cognito_user(username: str) -> bool:
    """
    Cognito UserPool に該当ユーザーがいて、ステータスが有効なら True を返す
    """
    try:
        resp = cognito.admin_get_user(
            UserPoolId=USER_POOL_ID,
            Username=username
        )
    except ClientError as e:
        # UserNotFoundException とかになったらNG
        print(f"Cognito lookup failed for {username}: {e}")
        return False

    # 例: resp["UserStatus"] が "CONFIRMED" ならOK、といった判定を入れる
    # UserStatus の典型値: FORCE_CHANGE_PASSWORD / CONFIRMED / ARCHIVED / ...
    user_status = resp.get("UserStatus")
    enabled = True
    for attr in resp.get("UserAttributes", []):
        if attr["Name"] == "custom:disabled" and attr["Value"].lower() == "true":
            enabled = False

    if user_status != "CONFIRMED":
        print(f"user {username} status not CONFIRMED: {user_status}")
        return False
    if not enabled:
        print(f"user {username} is disabled by custom attr")
        return False

    return True
