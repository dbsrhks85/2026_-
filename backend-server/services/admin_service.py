from datetime import datetime, timezone

from passlib.context import CryptContext

from database import get_supabase

password_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    return password_context.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    return password_context.verify(password, password_hash)


def public_admin(admin: dict) -> dict:
    return {
        "id": admin["id"],
        "username": admin["username"],
        "name": admin.get("name") or admin["username"],
        "role": admin.get("role", "admin"),
    }


async def get_admin_by_username(username: str) -> dict | None:
    supabase = get_supabase()
    result = await supabase.table("admin_users").select(
        "id, username, password_hash, name, role, is_active"
    ).eq("username", username).execute()
    return result.data[0] if result.data else None


async def get_admin_by_id(admin_id: int) -> dict | None:
    supabase = get_supabase()
    result = await supabase.table("admin_users").select(
        "id, username, name, role, is_active"
    ).eq("id", admin_id).execute()
    return result.data[0] if result.data else None


async def touch_last_login(admin_id: int) -> None:
    supabase = get_supabase()
    await supabase.table("admin_users").update({
        "last_login_at": datetime.now(timezone.utc).isoformat(),
    }).eq("id", admin_id).execute()


async def upsert_admin_user(
    username: str,
    password: str,
    name: str | None = None,
    role: str = "admin",
) -> dict:
    supabase = get_supabase()
    result = await supabase.table("admin_users").upsert({
        "username": username,
        "password_hash": hash_password(password),
        "name": name or username,
        "role": role,
        "is_active": True,
    }, on_conflict="username").execute()
    return result.data[0]

