"""
システム状態 API エンドポイント
"""

import logging

from fastapi import APIRouter, Depends

from ...core import get_current_user, require_permission, sudo_wrapper
from ...core.audit_log import audit_log
from ...core.auth import TokenData

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/system", tags=["system"])


# ===================================================================
# エンドポイント
# ===================================================================


@router.get("/status")
async def get_system_status(
    current_user: TokenData = Depends(require_permission("read:status")),
):
    """
    システム状態を取得

    Args:
        current_user: 現在のユーザー（read:status 権限必須）

    Returns:
        システム状態（CPU, メモリ, ディスク, 稼働時間）
    """
    logger.info(f"System status requested by: {current_user.username}")

    try:
        # sudo ラッパー経由でシステム状態を取得
        status_data = sudo_wrapper.get_system_status()

        # 監査ログ記録
        audit_log.record(
            operation="system_status_view",
            user_id=current_user.user_id,
            target="system",
            status="success",
        )

        return status_data

    except Exception as e:
        logger.error(f"Failed to get system status: {e}")

        # 監査ログ記録（失敗）
        audit_log.record(
            operation="system_status_view",
            user_id=current_user.user_id,
            target="system",
            status="failure",
            details={"error": str(e)},
        )

        raise
