"""
sudo ラッパー呼び出しモジュール

CLAUDE.md のセキュリティ原則に従った安全な sudo 実行
"""

import json
import logging
import subprocess
from pathlib import Path
from typing import Any, Dict

logger = logging.getLogger(__name__)


class SudoWrapperError(Exception):
    """sudo ラッパー実行エラー"""

    pass


class SudoWrapper:
    """sudo ラッパー呼び出しクラス"""

    def __init__(self, wrapper_dir: str = "/usr/local/sbin"):
        """
        初期化

        Args:
            wrapper_dir: ラッパースクリプトのディレクトリ
        """
        self.wrapper_dir = Path(wrapper_dir)

        # テストファイルが存在するか確認
        test_file = self.wrapper_dir / "adminui-status.sh"

        # 開発環境では、プロジェクトの wrappers/ を使用
        if not test_file.exists():
            project_root = Path(__file__).parent.parent.parent
            self.wrapper_dir = project_root / "wrappers"
            logger.warning(
                f"Wrapper scripts not found at {wrapper_dir}, "
                f"using development directory: {self.wrapper_dir}"
            )

    def _execute(self, wrapper_name: str, args: list[str], timeout: int = 30) -> Dict[str, Any]:
        """
        ラッパースクリプトを実行

        Args:
            wrapper_name: ラッパースクリプト名（例: adminui-status.sh）
            args: 引数リスト
            timeout: タイムアウト（秒）

        Returns:
            実行結果の辞書

        Raises:
            SudoWrapperError: 実行失敗時
        """
        wrapper_path = self.wrapper_dir / wrapper_name

        if not wrapper_path.exists():
            error_msg = f"Wrapper script not found: {wrapper_path}"
            logger.error(error_msg)
            raise SudoWrapperError(error_msg)

        # ラッパースクリプトの実行（配列渡し）
        # 注意: shell=True は絶対に使用しない
        cmd = ["sudo", str(wrapper_path)] + args

        logger.info(f"Executing wrapper: {wrapper_name}, args={args}")

        try:
            result = subprocess.run(
                cmd,
                check=True,
                capture_output=True,
                text=True,
                timeout=timeout,
            )

            logger.info(f"Wrapper execution successful: {wrapper_name}")

            # JSON レスポンスをパース
            try:
                output = json.loads(result.stdout)
                return output
            except json.JSONDecodeError:
                # JSON でない場合はそのまま返す
                return {"status": "success", "output": result.stdout.strip()}

        except subprocess.TimeoutExpired:
            error_msg = f"Wrapper execution timed out: {wrapper_name}"
            logger.error(error_msg)
            raise SudoWrapperError(error_msg)

        except subprocess.CalledProcessError as e:
            error_msg = f"Wrapper execution failed: {wrapper_name}"
            logger.error(f"{error_msg}, stderr={e.stderr}")

            # エラー出力を JSON としてパース試行
            try:
                error_data = json.loads(e.stderr or e.stdout or "{}")
                return error_data
            except json.JSONDecodeError:
                raise SudoWrapperError(f"{error_msg}: {e.stderr}")

        except Exception as e:
            error_msg = f"Unexpected error during wrapper execution: {wrapper_name}"
            logger.error(f"{error_msg}: {e}")
            raise SudoWrapperError(f"{error_msg}: {str(e)}")

    def get_system_status(self) -> Dict[str, Any]:
        """
        システム状態を取得

        Returns:
            システム状態の辞書
        """
        return self._execute("adminui-status.sh", [])

    def restart_service(self, service_name: str) -> Dict[str, Any]:
        """
        サービスを再起動

        Args:
            service_name: サービス名

        Returns:
            実行結果の辞書
        """
        return self._execute("adminui-service-restart.sh", [service_name])

    def get_logs(self, service_name: str, lines: int = 100) -> Dict[str, Any]:
        """
        サービスのログを取得

        Args:
            service_name: サービス名
            lines: 取得行数

        Returns:
            ログデータの辞書
        """
        return self._execute("adminui-logs.sh", [service_name, str(lines)])


# グローバルインスタンス
sudo_wrapper = SudoWrapper()
