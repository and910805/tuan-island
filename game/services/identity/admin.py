"""Local operator administration. Secret values are written to new files only."""
import argparse
import json
import os
from pathlib import Path
import sys
from identity_store import IdentityStore


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", required=True)
    sub = parser.add_subparsers(dest="operation", required=True)
    account = sub.add_parser("account-create")
    account.add_argument("--name", required=True)
    account.add_argument("--output-file", required=True)
    world = sub.add_parser("world-key")
    world.add_argument("--world-id", required=True)
    world.add_argument("--output-file", required=True)
    rotate = sub.add_parser("account-rotate")
    rotate.add_argument("--account-id", required=True)
    rotate.add_argument("--output-file", required=True)
    disable = sub.add_parser("account-disable")
    disable.add_argument("--account-id", required=True)
    args = parser.parse_args()
    store = IdentityStore(args.database)
    if args.operation == "account-disable":
        store.disable_account(args.account_id)
        print("ACCOUNT_DISABLED")
        return
    # Exclusive create prevents overwriting the operator's previous credentials.
    # On Windows use an operator-private directory; no machine ACL is changed.
    output = Path(args.output_file)
    fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        if args.operation == "account-create":
            record = store.provision_account(args.name)
            serialized = json.dumps(record, ensure_ascii=False, indent=2) + "\n"
        elif args.operation == "world-key":
            serialized = store.provision_world(args.world_id) + "\n"
        else:
            record = {"account_id": args.account_id, "credential": store.rotate_account(args.account_id)}
            serialized = json.dumps(record, ensure_ascii=False, indent=2) + "\n"
        stream.write(serialized)
        stream.flush()
        os.fsync(stream.fileno())
    print("CREDENTIAL_WRITTEN")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Do not print exceptions that may include paths, records or credentials.
        print("操作失敗。請檢查資料庫與輸出檔；若已變更憑證但檔案無法保存，請重新輪替。", file=sys.stderr)
        raise SystemExit(1)
