from fastapi import APIRouter, Depends, Form, HTTPException, status

from core.admin_auth import get_current_admin_payload
from core.security import create_admin_access_token
from services.admin_service import (
    get_admin_by_id,
    get_admin_by_username,
    public_admin,
    touch_last_login,
    verify_password,
)

router = APIRouter(prefix="/admin/auth", tags=["admin-auth"])


@router.post("/login")
async def login_admin(
    username: str = Form(...),
    password: str = Form(...),
):
    admin = await get_admin_by_username(username.strip())
    if not admin or not verify_password(password, admin.get("password_hash") or ""):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="아이디 또는 비밀번호가 올바르지 않습니다.",
        )
    if not admin.get("is_active", True):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="비활성화된 관리자 계정입니다.",
        )

    await touch_last_login(admin["id"])
    return {
        "access_token": create_admin_access_token(admin),
        "token_type": "bearer",
        "admin": public_admin(admin),
    }


@router.get("/me")
async def get_admin_me(current_admin: dict = Depends(get_current_admin_payload)):
    admin = await get_admin_by_id(current_admin["admin_id"])
    if not admin or not admin.get("is_active", True):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="관리자 계정을 확인할 수 없습니다.")
    return {"admin": public_admin(admin)}


@router.post("/logout")
async def logout_admin(_: dict = Depends(get_current_admin_payload)):
    return {"success": True}

