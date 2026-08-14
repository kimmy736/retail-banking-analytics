# -*- coding: utf-8 -*-
"""
Buổi 0 — Nạp & profiling dữ liệu Czech Bank (Berka, PKDD'99).

Việc script này làm:
  1. Tìm 8 bảng trong data/bronze (chấp nhận .asc / .csv / .tsv, tự đoán dấu phân cách)
  2. Đối chiếu số dòng thực tế với số dòng công bố  -> phát hiện tải thiếu/lỗi
  3. In schema + profiling từng bảng để bạn tự chốt các quyết định làm sạch

Đây KHÔNG phải bước làm sạch. Làm sạch nằm ở Buổi 2.
Mục tiêu duy nhất của script này: bạn nhìn thấy dữ liệu thật trước khi động vào nó.

Cách chạy:
    python scripts/01_prepare_data.py
"""
import sys
from pathlib import Path

import duckdb

BRONZE = Path('data/bronze')

# Số dòng công bố trong tài liệu gốc PKDD'99.
# Dùng để kiểm tra tải đủ chưa — đừng bao giờ tin file tải về là đúng khi chưa đếm.
EXPECTED = {
    'account':     4_500,
    'card':          892,
    'client':      5_369,
    'disp':        5_369,
    'district':       77,
    'loan':          682,
    'order':       6_471,
    'trans':   1_056_320,
}

# 'order' là từ khoá SQL -> đặt tên view khác để khỏi phải quote mọi nơi.
VIEW_NAME = {'order': 'orders'}

EXTS = ('.asc', '.csv', '.tsv', '.ASC', '.CSV', '.TSV')


def find_files() -> dict:
    """Tìm file của từng bảng, không phân biệt hoa thường và phần mở rộng."""
    found, missing = {}, []
    for table in EXPECTED:
        hit = next((p for ext in EXTS
                    for p in BRONZE.glob(f'{table}{ext}')), None)
        if hit is None:
            missing.append(table)
        else:
            found[table] = hit

    if missing:
        print('[LOI] Khong tim thay cac bang: ' + ', '.join(missing))
        print(f'      Kiem tra lai thu muc {BRONZE.as_posix()}/')
        print('      Xem muc "Cach chay" trong README de biet lenh tai.')
        sys.exit(1)
    return found


def register(con, files: dict) -> None:
    """Tạo view cho từng bảng. Để DuckDB tự đoán dấu phân cách (; hay ,)."""
    print('[1/3] Nap du lieu vao DuckDB\n')
    for table, path in files.items():
        view = VIEW_NAME.get(table, table)
        con.sql(f"""
            CREATE OR REPLACE VIEW {view} AS
            SELECT * FROM read_csv('{path.as_posix()}', auto_detect = true)
        """)
        print(f'      {view:<10} <- {path.name}')


def validate(con, files: dict) -> None:
    """Đếm dòng thật và so với số công bố."""
    print('\n[2/3] Doi chieu so dong voi tai lieu goc\n')
    print(f'      {"bang":<10} {"thuc te":>12} {"cong bo":>12}   ket qua')
    print('      ' + '-' * 48)

    all_ok = True
    for table in EXPECTED:
        view = VIEW_NAME.get(table, table)
        actual = con.sql(f'SELECT COUNT(*) FROM {view}').fetchone()[0]
        expected = EXPECTED[table]
        ok = actual == expected
        all_ok &= ok
        print(f'      {view:<10} {actual:>12,} {expected:>12,}   '
              f'{"OK" if ok else "!! LECH"}')

    print()
    if not all_ok:
        print('      => Co bang bi lech. Nguyen nhan thuong gap:')
        print('         - Tai nham ban re-upload da bi loc bot dong')
        print('         - Doc sai dau phan cach (file goc .asc dung dau ;)')
        print('         Bao lai cho mentor truoc khi di tiep.')
    else:
        print('      => Du lieu day du. Di tiep duoc.')


def profile(con) -> None:
    """In những thứ bạn PHẢI biết trước khi thiết kế data model."""
    print('\n[3/3] Profiling — doc ky phan nay, day la bai tap dau tien cua ban\n')

    blocks = [
        ('Cot cua tung bang (dung de tim khoa chinh / khoa ngoai)', """
            SELECT table_name, STRING_AGG(column_name, ', ' ORDER BY ordinal_position) AS cac_cot
            FROM information_schema.columns
            WHERE table_schema = 'main'
            GROUP BY 1 ORDER BY 1
        """),

        ('trans — khoang thoi gian (quyet dinh pham vi Dim_Date)', """
            SELECT MIN(date) AS ngay_nho_nhat,
                   MAX(date) AS ngay_lon_nhat,
                   COUNT(DISTINCT account_id) AS so_tai_khoan
            FROM trans
        """),

        ('trans — cac gia tri cua type / operation (se phai dich sang tieng Anh)', """
            SELECT type, operation, COUNT(*) AS so_dong,
                   ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
            FROM trans GROUP BY 1, 2 ORDER BY so_dong DESC
        """),

        ('loan — phan bo status (A/B = da tat toan, C/D = dang chay)', """
            SELECT status, COUNT(*) AS so_khoan,
                   ROUND(AVG(amount), 0) AS so_tien_tb,
                   ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
            FROM loan GROUP BY 1 ORDER BY 1
        """),

        ('disp — mot tai khoan co the co nhieu nguoi (OWNER / DISPONENT)', """
            SELECT type, COUNT(*) AS so_dong FROM disp GROUP BY 1 ORDER BY 2 DESC
        """),

        ('account — tan suat sao ke', """
            SELECT frequency, COUNT(*) AS so_dong FROM account GROUP BY 1 ORDER BY 2 DESC
        """),

        ('CANH BAO cardinality: bao nhieu client tren mot account?', """
            SELECT so_client_tren_account, COUNT(*) AS so_account FROM (
                SELECT account_id, COUNT(*) AS so_client_tren_account
                FROM disp GROUP BY 1
            ) GROUP BY 1 ORDER BY 1
        """),
    ]

    for title, sql in blocks:
        print(f'--- {title}')
        print(con.sql(sql))
        print()

    print('=' * 70)
    print('CAU HOI CHO BAN (tra loi truoc Buoi 1):')
    print('  1. Bang nao la FACT? Vi sao?')
    print('  2. Tai sao khong the noi truc tiep client voi account?')
    print('  3. Bang disp co 5369 dong, account co 4500 -> dieu do noi len gi')
    print('     ve quan he giua client va account?')
    print('  4. Cot date trong trans dang o kieu gi? No co dung la ngay khong?')
    print('=' * 70)


if __name__ == '__main__':
    if not BRONZE.exists():
        sys.exit(f'Khong thay thu muc {BRONZE.as_posix()}/ — chay tu goc repo.')

    files = find_files()
    con = duckdb.connect()
    register(con, files)
    validate(con, files)
    profile(con)
