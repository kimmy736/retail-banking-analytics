# -*- coding: utf-8 -*-
"""
Chạy sql/01_silver.sql và lưu kết quả vào data/silver/.

Bạn KHÔNG cần sửa file này. Việc của bạn là viết sql/01_silver.sql.

Cách chạy:
    python scripts/02_build_silver.py
"""
from pathlib import Path

import duckdb

BRONZE = Path('data/bronze')
SILVER = Path('data/silver')
SQL = Path('sql/01_silver.sql')

RAW = ['account', 'card', 'client', 'disp', 'district', 'loan', 'trans']


def main() -> None:
    if not SQL.exists():
        raise SystemExit(f'Chua co {SQL} — do la file ban can viet.')

    SILVER.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()

    # Dang ky file tho thanh view. 'order' la tu khoa SQL nen doi ten thanh 'orders'.
    for t in RAW:
        con.sql(f"CREATE VIEW {t} AS "
                f"SELECT * FROM read_csv('{(BRONZE/f'{t}.csv').as_posix()}', auto_detect=true)")
    con.sql(f"CREATE VIEW orders AS "
            f"SELECT * FROM read_csv('{(BRONZE/'order.csv').as_posix()}', auto_detect=true)")

    con.sql(SQL.read_text(encoding='utf-8'))

    # Bang nao ban tao co tien to silver_ thi se duoc xuat ra parquet.
    made = [r[0] for r in con.sql(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema='main' AND table_name LIKE 'silver_%' ORDER BY 1").fetchall()]

    if not made:
        raise SystemExit('Khong thay bang nao ten silver_*. Dat ten bang bat dau bang silver_.')

    print(f'{"bang":<26}{"so dong":>12}   -> file')
    print('-' * 70)
    for t in made:
        n = con.sql(f'SELECT COUNT(*) FROM {t}').fetchone()[0]
        out = SILVER / f'{t}.parquet'
        con.sql(f"COPY {t} TO '{out.as_posix()}' (FORMAT parquet)")
        print(f'{t:<26}{n:>12,}   -> {out.name}')

    print(f'\nXong. {len(made)} bang trong {SILVER.as_posix()}/')


if __name__ == '__main__':
    main()
