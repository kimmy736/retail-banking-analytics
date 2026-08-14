# -*- coding: utf-8 -*-
"""
Chạy sql/02_gold.sql và lưu kết quả vào data/gold/.

Bạn KHÔNG cần sửa file này. Việc của bạn là viết sql/02_gold.sql.

Đọc từ data/silver/*.parquet, xuất ra data/gold/*.parquet — đây là các bảng
sẽ nạp vào Power BI.

Cách chạy:
    python scripts/03_build_gold.py
"""
from pathlib import Path

import duckdb

SILVER = Path('data/silver')
GOLD = Path('data/gold')
SQL = Path('sql/02_gold.sql')


def main() -> None:
    if not SQL.exists():
        raise SystemExit(f'Chua co {SQL} — do la file ban can viet.')

    files = sorted(SILVER.glob('silver_*.parquet'))
    if not files:
        raise SystemExit('Khong thay file nao trong data/silver/. '
                         'Chay scripts/02_build_silver.py truoc.')

    GOLD.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()

    for f in files:
        con.sql(f"CREATE VIEW {f.stem} AS SELECT * FROM '{f.as_posix()}'")
    print('Nap tu silver:', ', '.join(f.stem for f in files), '\n')

    con.sql(SQL.read_text(encoding='utf-8'))

    made = [r[0] for r in con.sql(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema='main' AND table_type='BASE TABLE' "
        "AND (table_name LIKE 'dim_%' OR table_name LIKE 'fact_%') "
        "ORDER BY table_name").fetchall()]

    if not made:
        raise SystemExit('Khong thay bang nao ten dim_* hoac fact_*.')

    print(f'{"bang":<26}{"so dong":>12}   -> file')
    print('-' * 70)
    for t in made:
        n = con.sql(f'SELECT COUNT(*) FROM {t}').fetchone()[0]
        out = GOLD / f'{t}.parquet'
        con.sql(f"COPY {t} TO '{out.as_posix()}' (FORMAT parquet)")
        print(f'{t:<26}{n:>12,}   -> {out.name}')

    print(f'\nXong. {len(made)} bang trong {GOLD.as_posix()}/')


if __name__ == '__main__':
    main()
