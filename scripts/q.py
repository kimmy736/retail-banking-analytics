# -*- coding: utf-8 -*-
"""
Chạy nhanh một câu SQL bất kỳ trên dữ liệu bronze. Dùng để dò dữ liệu.

Cách dùng:
    python scripts/q.py "SELECT * FROM district LIMIT 5"
    python scripts/q.py -f sql/thu_nghiem.sql

8 bảng đã đăng ký sẵn: account, card, client, disp, district, loan, orders, trans
(bảng 'order' đổi tên thành 'orders' vì 'order' là từ khoá SQL)
"""
import sys
from pathlib import Path

import duckdb

sys.stdout.reconfigure(encoding='utf-8')

BRONZE = Path('data/bronze')
RAW = ['account', 'card', 'client', 'disp', 'district', 'loan', 'trans']


def connect() -> duckdb.DuckDBPyConnection:
    con = duckdb.connect()
    for t in RAW:
        con.sql(f"CREATE VIEW {t} AS "
                f"SELECT * FROM read_csv('{(BRONZE/f'{t}.csv').as_posix()}', auto_detect=true)")
    con.sql(f"CREATE VIEW orders AS "
            f"SELECT * FROM read_csv('{(BRONZE/'order.csv').as_posix()}', auto_detect=true)")
    return con


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)

    if sys.argv[1] == '-f':
        sql = Path(sys.argv[2]).read_text(encoding='utf-8')
    else:
        sql = ' '.join(sys.argv[1:])

    con = connect()
    for stmt in [s.strip() for s in sql.split(';') if s.strip()]:
        result = con.sql(stmt)
        if result is not None:
            print(result)
