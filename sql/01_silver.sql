--SILVER — làm sạch dữ liệu thô
--   - đổi kiểu dữ liệu về đúng bản chất
--   - dịch mã tiếng Séc sang tiếng Anh
--   - đặt tên cột đọc được
-- Chạy:  python scripts/02_build_silver.py

-- 1. DISTRICT — 77 quận, kèm chỉ số kinh tế xã hội
-- Cột gốc tên A1..A16 nên không ai đọc được. Đổi hết sang tên có nghĩa.
-- Bỏ A5..A8 (số xã chia theo quy mô dân số) project không dùng
--
-- A12 và A15 cần TRY_CAST vì có kiểu dữ liệu hỗn hợp: số và ký tự '?'. Nếu gặp ký tự '?' thì trả về NULL.
-- biến giá trị rác thành NULL.
CREATE OR REPLACE TABLE silver_district AS
SELECT
    A1 AS district_id,
    A2 AS district_name,
    A3 AS region,
    A4 AS population,
    A9 AS n_cities,
    A10 AS urban_ratio_pct,
    A11 AS avg_salary,

    -- district 69 (Jesenik) mang giá trị '?' ở A12 và A15.
    -- Giữ NULL, KHÔNG điền thay thế, nếu điền bằng số liệu 1996 thì mức
    -- thay đổi 95->96 của Jesenik sẽ bằng 0, tạo ra một phát hiện giả.
    -- Ảnh hưởng 48/4.500 tài khoản (1,1%). Xem README mục Làm sạch.
    TRY_CAST(A12 AS DOUBLE) AS unemployment_95,
    A13 AS unemployment_96,

    A14 AS entrepreneurs_per_1000,

    -- Số vụ phạm tội là số đếm -> INTEGER, không phải DOUBLE.
    TRY_CAST(A15 AS INTEGER) AS crimes_95,
    A16 AS crimes_96
FROM district;

-- 2. ACCOUNT — 4.500 tài khoản
-- Hai việc phải xử lý:
-- a) date đang là số nguyên dạng YYMMDD (930101), không phải kiểu ngày
-- b) frequency là mã tiếng Séc
CREATE TABLE silver_account AS
SELECT
    account_id,
    district_id,
    -- POPLATEK = phí, MESICNE = hàng tháng, TYDNE = hàng tuần,
    -- PO OBRATU = sau mỗi lần phát sinh giao dịch.
    -- ELSE giữ nguyên giá trị gốc: nếu nguồn xuất hiện mã lạ, ta nhìn thấy nó
    -- thay vì để nó âm thầm thành NULL.
    CASE frequency
        WHEN 'POPLATEK MESICNE'   THEN 'Monthly'
        WHEN 'POPLATEK TYDNE'     THEN 'Weekly'
        WHEN 'POPLATEK PO OBRATU' THEN 'After transaction'
        ELSE frequency
    END AS statement_frequency,

    -- strptime chỉ nhận chuỗi nên phải CAST sang VARCHAR trước.
    -- '%y' (y thường) hiểu 93 là 1993; '%Y' (Y hoa) sẽ hiểu 93 là năm 93.
    -- Kết quả strptime là TIMESTAMP -> ép về DATE cho gọn.
    strptime(CAST(date AS VARCHAR), '%y%m%d')::DATE AS opened_date
FROM account;

-- 3. DISP — quan hệ giữa khách hàng và tài khoản

-- Bảng gốc có 5.369 dòng: 4.500 OWNER (chủ tài khoản) + 869 DISPONENT
-- (người được uỷ quyền sử dụng).
--
-- Chỉ giữ OWNER. Lý do: 869 tài khoản có 2 người, nên nếu giữ cả DISPONENT
-- thì mỗi giao dịch của các tài khoản đó bị khớp 2 lần khi JOIN
--
-- Đánh đổi: mất thông tin về người được uỷ quyền. Chấp nhận được vì
-- project phân tích ở cấp CHỦ TÀI KHOẢN. 
--
-- Sau bước này: 4.500 dòng, quan hệ 1-1 với account.
CREATE OR REPLACE TABLE silver_disp AS
SELECT
    disp_id,
    client_id,
    account_id
FROM disp
WHERE type = 'OWNER';

-- 
-- 4. CLIENT — 5.369 khách hàng
-- 
-- birth_number ma hoa 2 thong tin trong 1 con so (ma dinh danh Sec):
--   YYMMDD, va nu duoc cong 50 vao phan thang.
-- Tach ra thanh birth_date + gender. Xem notebook 01_profiling

CREATE TABLE silver_client AS
WITH tach AS (
    SELECT
        client_id,
        district_id,
        birth_number // 10000         AS yy,
        (birth_number // 100) % 100   AS mm_ma_hoa,
        birth_number % 100            AS dd
    FROM client
)
SELECT
    client_id,
    district_id,

    CASE WHEN mm_ma_hoa > 12 THEN 'Female' ELSE 'Male' END AS gender,

    make_date(
        1900 + yy,
        CASE WHEN mm_ma_hoa > 12 THEN mm_ma_hoa - 50 ELSE mm_ma_hoa END,
        dd
    ) AS birth_date
FROM tach;


-- 
-- 5. TRANS — 1.056.320 giao dich 
-- 
-- Bon viec phai xu ly, xem notebook 01_profiling:
--   date la so nguyen YYMMDD
--  operation rong 183.114 dong (NULL co cau truc, khong phai thieu)
--  type co 3 gia tri, VYBER trung nghia voi VYDAJ
--   k_symbol co ca NULL lan chuoi khoang trang
CREATE OR REPLACE TABLE silver_trans AS
SELECT
    trans_id,
    account_id,

    strptime(CAST(date AS VARCHAR), '%y%m%d')::DATE AS trans_date,

    -- Gop VYBER vao VYDAJ: ca hai deu la tien ra, chi khac cach ghi.
    -- Xac nhan bang crosstab o notebook — VYBER chi di kem operation VYBER.
    CASE type
        WHEN 'PRIJEM' THEN 'Credit'
        WHEN 'VYDAJ'  THEN 'Debit'
        WHEN 'VYBER'  THEN 'Debit'
        ELSE type
    END AS direction,

    -- operation NULL = lai ngan hang tu ghi co, khach khong thao tac gi.
    -- Dien nhan dung nghia thay vi 'Unknown' — ta biet ro no la gi.
    CASE
        WHEN operation IS NULL              THEN 'Interest credit'
        WHEN operation = 'VYBER'            THEN 'Cash withdrawal'
        WHEN operation = 'VKLAD'            THEN 'Cash deposit'
        WHEN operation = 'PREVOD NA UCET'   THEN 'Transfer out'
        WHEN operation = 'PREVOD Z UCTU'    THEN 'Transfer in'
        WHEN operation = 'VYBER KARTOU'     THEN 'Card withdrawal'
        ELSE operation
    END AS operation,

    amount,

    -- Giu nguyen so du am: do la thau chi, tin hieu nghiep vu that.
    balance,

    -- NULLIF(TRIM(...)) quy ca NULL lan chuoi khoang trang ve mot moi.
    CASE NULLIF(TRIM(k_symbol), '')
        WHEN 'UROK'        THEN 'Interest credited'
        WHEN 'SANKC. UROK' THEN 'Penalty interest'
        WHEN 'SLUZBY'      THEN 'Service fee'
        WHEN 'SIPO'        THEN 'Household payment'
        WHEN 'DUCHOD'      THEN 'Pension'
        WHEN 'POJISTNE'    THEN 'Insurance payment'
        WHEN 'UVER'        THEN 'Loan payment'
        ELSE NULLIF(TRIM(k_symbol), '')
    END AS purpose
FROM trans;