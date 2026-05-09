import os

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from core.security import bearer_scheme, decode_access_token

ADMIN_API_KEY = os.getenv("ADMIN_API_KEY", "").strip()


async def get_current_admin_payload(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> dict:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="관리자 로그인이 필요합니다.")

    payload = decode_access_token(credentials.credentials)
    if payload.get("type") != "admin" or payload.get("role") not in ("admin", "super_admin"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="관리자 권한이 필요합니다.")
    return payload


async def require_admin(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    x_admin_api_key: str | None = Header(default=None),
):
    if credentials is not None and credentials.scheme.lower() == "bearer":
        return await get_current_admin_payload(credentials)
    if not ADMIN_API_KEY or x_admin_api_key != ADMIN_API_KEY:
        raise HTTPException(status_code=401, detail="관리자 인증이 필요합니다.")
    return {"type": "admin", "role": "admin", "auth": "api_key"}
