import asyncio
import getpass
import os
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT_DIR))

from database import init_supabase  # noqa: E402
from services.admin_service import upsert_admin_user  # noqa: E402


async def main():
    username = os.getenv("ADMIN_USERNAME") or input("Admin username: ").strip()
    name = os.getenv("ADMIN_NAME") or input("Admin display name: ").strip() or username
    role = os.getenv("ADMIN_ROLE") or "admin"
    password = os.getenv("ADMIN_PASSWORD")

    if not password:
        password = getpass.getpass("Admin password: ")
        password_confirm = getpass.getpass("Confirm password: ")
        if password != password_confirm:
            raise SystemExit("Passwords do not match.")

    if not username:
        raise SystemExit("ADMIN_USERNAME is required.")
    if len(password) < 8:
        raise SystemExit("Admin password must be at least 8 characters.")
    if role not in ("admin", "super_admin"):
        raise SystemExit("ADMIN_ROLE must be admin or super_admin.")

    await init_supabase()
    admin = await upsert_admin_user(
        username=username,
        password=password,
        name=name,
        role=role,
    )
    print(f"Admin user is ready: username={admin['username']}, role={admin.get('role', role)}")


if __name__ == "__main__":
    asyncio.run(main())
