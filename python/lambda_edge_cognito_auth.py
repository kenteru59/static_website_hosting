import json
import jwt
import urllib.request
from jwt.algorithms import RSAAlgorithm
import time

USER_POOL_ID = ""  # 環境変数で渡される
COGNITO_REGION = ""  # 例: ap-northeast-1

JWKS_CACHE = {"keys": None, "fetched_at": 0, "ttl": 3600}


def handler(event, context):
    request = event["Records"][0]["cf"]["request"]
    headers = request.get("headers", {})

    # Authorizationヘッダを確認
    auth_header = headers.get("authorization", [{"value": ""}])[0]["value"]
    if not auth_header.startswith("Bearer "):
        print("No Bearer token found.")
        return _redirect_to_login()

    token = auth_header[len("Bearer "):]

    try:
        payload = _verify_jwt(token)
        print(f"JWT verified for user: {payload.get('email')}")
        return request

    except Exception as e:
        print(f"JWT verification failed: {e}")
        return _redirect_to_login()


def _verify_jwt(token: str):
    """Cognito JWTを署名検証・有効期限確認"""
    global JWKS_CACHE
    now = time.time()

    # JWKSキャッシュ
    if not JWKS_CACHE["keys"] or now - JWKS_CACHE["fetched_at"] > JWKS_CACHE["ttl"]:
        jwks_url = f"https://cognito-idp.{COGNITO_REGION}.amazonaws.com/{USER_POOL_ID}/.well-known/jwks.json"
        print(f"Fetching JWKS from {jwks_url}")
        with urllib.request.urlopen(jwks_url) as response:
            JWKS_CACHE["keys"] = json.loads(response.read())["keys"]
            JWKS_CACHE["fetched_at"] = now

    headers = jwt.get_unverified_header(token)
    kid = headers["kid"]

    # kidに合う公開鍵を探す
    key_data = next((k for k in JWKS_CACHE["keys"] if k["kid"] == kid), None)
    if not key_data:
        raise Exception("Public key not found for KID")

    public_key = RSAAlgorithm.from_jwk(json.dumps(key_data))

    # 署名と有効期限を検証
    payload = jwt.decode(
        token,
        public_key,
        algorithms=["RS256"],
        audience=None,  # audienceを制限したい場合はClient IDなど指定
        options={"require": ["exp", "iat"]}
    )
    return payload


def _redirect_to_login():
    return {
        "status": "302",
        "statusDescription": "Found",
        "headers": {
            "location": [{"key": "Location", "value": "https://example.com/login"}],
            "cache-control": [{"key": "Cache-Control", "value": "no-cache"}],
        },
    }
