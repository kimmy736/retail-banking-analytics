-- =====================================================================
-- GOLD — dựng star schema cho Power BI
-- =====================================================================
-- "Dựng star schema cho Power BI" = chuẩn bị lại dữ liệu thành một mô hình
-- có cấu trúc rõ ràng để Power BI có thể tính toán, lọc và làm dashboard
-- chính xác.
--
-- ---------------------------------------------------------------------
-- MỤC TIÊU
-- ---------------------------------------------------------------------
-- Sắp xếp lại 5 bảng ở tầng silver thành một mô hình dễ dùng cho Power BI.
-- Bảng giao dịch nằm ở giữa, các bảng còn lại cung cấp thông tin để lọc
-- và phân tích.
--
-- ĐẦU VÀO   data/silver/silver_*.parquet   (do scripts/02_build_silver.py tạo)
-- ĐẦU RA    data/gold/*.parquet            (nạp thẳng vào Power BI)
--
-- Chạy bằng:
--     python scripts/03_build_gold.py
--
-- ---------------------------------------------------------------------
-- MÔ HÌNH SAU KHI DỰNG
-- ---------------------------------------------------------------------
--                        dim_date (2.191)
--                              |
--   dim_client (4.500) --- fact_transaction --- dim_account (4.500)
--                        (1.056.320 dòng)
--                              |
--                       dim_district (77)
--
-- fact_transaction : 1 dòng = 1 giao dịch. Chứa số tiền và số dư để tính
--                    toán (amount, balance) và các khoá nối tới dimension.
--
-- dim_* : mô tả "ai / ở đâu / khi nào". Dùng để lọc và nhóm.
--
--   dim_client   : thông tin khách hàng, dùng để phân tích theo giới tính,
--                  ngày sinh, nhóm tuổi.
--   dim_account  : thông tin tài khoản, dùng để phân tích theo tài khoản,
--                  ngày mở tài khoản, khu vực.
--   dim_district : thông tin khu vực — dân số, mức lương, tỷ lệ thất nghiệp.
--   dim_date     : bảng ngày được tự tạo vì dữ liệu gốc không có bảng lịch
--                  riêng. Giúp Power BI phân tích theo năm, quý, tháng,
--                  ngày, cuối tuần và các chỉ số theo thời gian.
--
-- Bộ lọc chảy MỘT CHIỀU từ dimension xuống fact. Chọn "Nữ" ở dim_client
-- thì fact chỉ còn giao dịch của khách nữ.
--
-- ---------------------------------------------------------------------
-- TẠI SAO PHẢI DỰNG NHƯ VẬY
-- ---------------------------------------------------------------------
-- 1. Tạo dim_date
--
-- Dữ liệu giao dịch chỉ có ngày giao dịch, không có sẵn bảng ngày để phân
-- tích. Vì vậy phải tự tạo dim_date. Nhờ đó Power BI có thể phân tích theo
-- năm, tháng, quý, so sánh các khoảng thời gian và tính chỉ số luỹ kế.
--
-- 2. Đưa client_id và district_id vào fact_transaction
--
-- Về lý thuyết có thể đi vòng: giao dịch -> tài khoản -> khách hàng.
-- Cách nối vòng nhiều tầng đó gọi là snowflake. Nó có hai nhược điểm:
--   - chậm hơn, vì Power BI phải đi qua từng bậc quan hệ mỗi lần tính
--   - dễ sai chiều lọc khi viết DAX
--
-- Star schema chấp nhận lặp lại khoá trên bảng fact để đổi lấy mô hình
-- phẳng: mọi dimension nối thẳng vào fact, chỉ một bậc.
--
-- 3. Tạo signed_amount
--
-- Trong dữ liệu gốc, amount luôn là số dương. Muốn biết tiền đi vào hay
-- đi ra phải nhìn thêm cột direction.
--
-- Vì vậy tạo thêm signed_amount:
--     Debit  -> số âm
--     Credit -> số dương
--
-- Nhờ vậy khi cần tính dòng tiền ròng chỉ cần SUM(signed_amount), thay vì
-- mỗi lần lại phải kiểm tra direction trong DAX.
--
-- ---------------------------------------------------------------------
-- CÁCH ĐẶT TÊN
-- ---------------------------------------------------------------------
-- dim_   = bảng thông tin dùng để lọc và phân tích
-- fact_  = bảng giao dịch dùng để tính toán
--
-- Hai tiền tố này cũng là cách scripts/03_build_gold.py nhận diện bảng
-- nào cần xuất ra file.
--
-- Tên cột viết bằng tiếng Anh, chữ thường và dùng dấu "_". Đây cũng là
-- những tên sẽ xuất hiện trong Power BI, nên cố gắng đặt tên sao cho nhìn
-- vào là hiểu.
-- =====================================================================


-- ---------------------------------------------------------------------
-- dim_date — bảng lịch, tự sinh từ 01/01/1993 đến 31/12/1998
-- ---------------------------------------------------------------------
-- 2.191 ngày = 6 năm, trong đó 1996 là năm nhuận.
-- year_month (dạng số 199301) dùng để SẮP XẾP đúng thứ tự thời gian;
-- year_month_label (dạng chữ 1993-01) dùng để HIỂN THỊ trên biểu đồ.
CREATE OR REPLACE TABLE dim_date AS
SELECT
    d::DATE                                   AS date,
    YEAR(d)                                   AS year,
    QUARTER(d)                                AS quarter,
    'Q' || QUARTER(d)                         AS quarter_name,
    MONTH(d)                                  AS month,
    MONTHNAME(d)                              AS month_name,
    CAST(STRFTIME(d, '%Y%m') AS INTEGER)      AS year_month,
    STRFTIME(d, '%Y-%m')                      AS year_month_label,
    DAY(d)                                    AS day,
    DAYNAME(d)                                AS day_name,
    ISODOW(d) >= 6                            AS is_weekend
FROM generate_series(DATE '1993-01-01', DATE '1998-12-31', INTERVAL 1 DAY) AS t(d);


-- ---------------------------------------------------------------------
-- dim_district — 77 quận kèm chỉ số kinh tế xã hội
-- ---------------------------------------------------------------------
-- unemployment_95 và crimes_95 có NULL ở quận 69 (Jesenik).
-- Đó là chủ ý, không phải lỗi — xem notebook 01_profiling, đầu mối 1.
CREATE OR REPLACE TABLE dim_district AS
SELECT
    district_id, district_name, region, population, n_cities,
    urban_ratio_pct, avg_salary,
    unemployment_95, unemployment_96,
    entrepreneurs_per_1000, crimes_95, crimes_96
FROM silver_district;


-- dim_account duoc dung o CUOI file, sau khi da co fact_account_monthly,
-- vi no can cac cot phan loai rui ro tinh tu bang do.


-- ---------------------------------------------------------------------
-- dim_client — 4.500 chủ tài khoản
-- ---------------------------------------------------------------------
-- silver_client có 5.369 người, nhưng 869 trong số đó là DISPONENT
-- (người được uỷ quyền) đã bị loại ở tầng silver.
--
-- Phải JOIN với silver_disp để loại nốt 869 người này. Nếu giữ lại,
-- model sẽ có hai con số khách hàng khác nhau:
--     COUNTROWS(dim_client)              -> 5.369
--     DISTINCTCOUNT(fact[client_id])     -> 4.500
-- và không ai giải thích được vì sao hai chỗ ra hai số.
--
-- age_1998 tính tại thời điểm kết thúc dữ liệu (31/12/1998) để mọi khách
-- được đo trên cùng một mốc.
CREATE OR REPLACE TABLE dim_client AS
WITH tuoi AS (
    SELECT
        c.client_id,
        c.gender,
        c.birth_date,
        DATE_DIFF('year', c.birth_date, DATE '1998-12-31') AS age_1998
    FROM silver_client c
    JOIN silver_disp   d ON c.client_id = d.client_id
)
SELECT
    client_id, gender, birth_date, age_1998,
    CASE
        WHEN age_1998 < 30 THEN '1. Dưới 30'
        WHEN age_1998 < 45 THEN '2. 30–44'
        WHEN age_1998 < 60 THEN '3. 45–59'
        ELSE                    '4. 60 trở lên'
    END AS age_band
FROM tuoi;


-- ---------------------------------------------------------------------
-- fact_transaction — 1.056.320 giao dịch
-- ---------------------------------------------------------------------
-- Hạt: 1 dòng = 1 giao dịch.
--
-- KIỂM TRA BẮT BUỘC sau khi chạy: số dòng phải giữ nguyên 1.056.320.
-- Nếu tăng lên nghĩa là một trong hai phép JOIN bên dưới đang nhân bản
-- dòng — dừng lại điều tra ngay, đừng nạp vào Power BI.
--
-- Hai JOIN này an toàn vì silver_disp đã lọc còn OWNER (4.500 dòng, khớp
-- 1-1 với account) và silver_account vốn đã 1 dòng một tài khoản.
CREATE OR REPLACE TABLE fact_transaction AS
SELECT
    t.trans_id,
    t.trans_date,
    t.account_id,
    d.client_id,
    a.district_id,
    t.direction,
    t.operation,
    t.purpose,
    t.amount,

    -- Xem mục 3 ở phần đầu file: gộp chiều tiền vào một cột có dấu.
    CASE WHEN t.direction = 'Debit' THEN -t.amount ELSE t.amount END AS signed_amount,

    -- balance là số dư luỹ kế sau giao dịch (semi-additive):
    -- cộng được theo tài khoản, KHÔNG cộng được theo thời gian.
    t.balance
FROM silver_trans   t
JOIN silver_disp    d ON t.account_id = d.account_id
JOIN silver_account a ON t.account_id = a.account_id;


-- ---------------------------------------------------------------------
-- fact_account_monthly — ảnh chụp từng tài khoản theo từng tháng
-- ---------------------------------------------------------------------
-- Hạt: 1 dòng = 1 tài khoản × 1 tháng. Khoảng 185.000 dòng.
--
-- VÌ SAO CẦN BẢNG NÀY
-- Cột balance là số dư luỹ kế (semi-additive): cộng được theo tài khoản
-- nhưng KHÔNG cộng được theo thời gian. Muốn biết "tổng số dư danh mục
-- tháng 6/1997" thì phải lấy số dư cuối tháng của từng tài khoản rồi cộng
-- lại — viết bằng DAX thì dài và chạy chậm trên 1 triệu dòng.
--
-- Tính sẵn ở đây thì trong Power BI chỉ còn SUM(end_balance).
-- Đây cũng là artifact chuẩn của phân tích ngân hàng bán lẻ.
--
-- ĐỐI SOÁT: tổng end_balance của tháng cuối (12/1998) phải bằng đúng
-- 197.140.234 Kč — tổng số dư cuối kỳ tính theo cách độc lập.
--
-- LƯU Ý VỀ THÁNG KHÔNG CÓ GIAO DỊCH
-- Bảng này tạo lưới đầy đủ mọi tháng kể từ ngày mở tài khoản, kể cả tháng
-- không phát sinh giao dịch nào. Lý do: tháng im lặng chính là tín hiệu
-- quan trọng nhất khi tìm khách sắp rời bỏ. Nếu chỉ giữ tháng có giao dịch
-- thì những khách đã ngừng hoạt động sẽ biến mất khỏi báo cáo — đúng nhóm
-- cần nhìn thấy nhất lại bị giấu đi.
-- Số dư của tháng im lặng được giữ nguyên theo tháng gần nhất có giao dịch.
CREATE OR REPLACE TABLE fact_account_monthly AS

WITH thang_co_giao_dich AS (
    SELECT
        account_id,
        DATE_TRUNC('month', trans_date)                               AS month_start,
        COUNT(*)                                                      AS n_transactions,
        SUM(CASE WHEN direction = 'Credit' THEN amount ELSE 0 END)    AS money_in,
        SUM(CASE WHEN direction = 'Debit'  THEN amount ELSE 0 END)    AS money_out,
        SUM(signed_amount)                                            AS net_flow,
        SUM(CASE WHEN purpose = 'Penalty interest' THEN 1 ELSE 0 END) AS n_penalty,
        MAX(CASE WHEN balance < 0 THEN 1 ELSE 0 END)                  AS had_negative_balance,

        -- ARG_MAX(x, y) tra ve x tai dong co y lon nhat.
        -- Tuc: lay balance cua giao dich CUOI CUNG trong thang.
        ARG_MAX(balance, (trans_date, trans_id))                      AS end_balance_raw
    FROM fact_transaction
    GROUP BY 1, 2
),

luoi AS (
    SELECT a.account_id, m.month_start
    FROM silver_account a
    CROSS JOIN (
        SELECT DISTINCT DATE_TRUNC('month', date) AS month_start FROM dim_date
    ) m
    WHERE m.month_start >= DATE_TRUNC('month', a.opened_date)
)

SELECT
    l.account_id,
    l.month_start,

    COALESCE(t.n_transactions, 0)       AS n_transactions,
    COALESCE(t.money_in, 0)             AS money_in,
    COALESCE(t.money_out, 0)            AS money_out,
    COALESCE(t.net_flow, 0)             AS net_flow,
    COALESCE(t.n_penalty, 0)            AS n_penalty,
    COALESCE(t.had_negative_balance, 0) AS had_negative_balance,

    -- Thang khong co giao dich -> giu so du cua thang gan nhat co giao dich.
    COALESCE(
        t.end_balance_raw,
        LAST_VALUE(t.end_balance_raw IGNORE NULLS) OVER (
            PARTITION BY l.account_id ORDER BY l.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
        0
    ) AS end_balance,

    (t.account_id IS NULL) AS is_inactive_month

FROM luoi l
LEFT JOIN thang_co_giao_dich t
       ON l.account_id = t.account_id AND l.month_start = t.month_start;


-- ---------------------------------------------------------------------
-- dim_account_risk — phân loại rủi ro rời bỏ cho từng tài khoản
-- ---------------------------------------------------------------------
-- Hạt: 1 dòng = 1 tài khoản. 4.500 dòng, khớp 1-1 với dim_account.
--
-- VÌ SAO TÍNH Ở SQL
-- Xác định "số dư giảm 3 tháng liên tiếp" đòi hỏi so sánh một dòng với ba
-- dòng trước đó của cùng tài khoản. DAX làm được nhưng công thức dài và
-- chạy chậm. SQL có window function nên viết gọn hơn nhiều.
--
-- GIẢ ĐỊNH VỀ THỜI ĐIỂM
-- Mọi chỉ số được tính tại mốc 12/1998 — tháng cuối cùng của dữ liệu.
-- Nghĩa là bảng này là ẢNH CHỤP tại một thời điểm, không thay đổi theo
-- bộ lọc thời gian trong Power BI. Phải ghi rõ điều này trong README:
-- người xem chọn năm 1995 vẫn thấy phân loại rủi ro của 12/1998.
--
-- ĐỊNH NGHĨA PHÂN NHÓM
--   Ngủ đông  : không giao dịch từ 6 tháng trở lên
--   Cảnh báo  : không giao dịch 3-5 tháng, HOẶC số dư giảm 3 tháng liên tiếp
--   Hoạt động : còn lại
-- Ngưỡng 3 và 6 tháng là lựa chọn, không phải chuẩn ngành. Chọn vậy vì
-- phần lớn tài khoản giao dịch hàng tháng (trung bình 3,3 giao dịch/tháng),
-- nên im lặng 3 tháng đã là bất thường.

CREATE OR REPLACE TABLE tinh_rui_ro AS

WITH moc AS (SELECT DATE '1998-12-01' AS thang_cuoi),

-- Thang gan nhat co giao dich cua moi tai khoan
hoat_dong_cuoi AS (
    SELECT account_id, MAX(month_start) AS thang_gd_cuoi
    FROM fact_account_monthly
    WHERE n_transactions > 0
    GROUP BY 1
),

-- So du 4 thang gan nhat, de xet xu huong 3 thang lien tiep
so_du_gan_day AS (
    SELECT
        account_id,
        end_balance,
        ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY month_start DESC) AS thu_tu
    FROM fact_account_monthly
),

xu_huong AS (
    SELECT
        account_id,
        MAX(CASE WHEN thu_tu = 1 THEN end_balance END) AS sd_t0,
        MAX(CASE WHEN thu_tu = 2 THEN end_balance END) AS sd_t1,
        MAX(CASE WHEN thu_tu = 3 THEN end_balance END) AS sd_t2,
        MAX(CASE WHEN thu_tu = 4 THEN end_balance END) AS sd_t3
    FROM so_du_gan_day
    WHERE thu_tu <= 4
    GROUP BY 1
),

tong_hop AS (
    SELECT
        a.account_id,
        h.thang_gd_cuoi,
        DATE_DIFF('month', h.thang_gd_cuoi, m.thang_cuoi)              AS thang_im_lang,
        x.sd_t0                                                        AS so_du_hien_tai,
        (x.sd_t0 < x.sd_t1 AND x.sd_t1 < x.sd_t2 AND x.sd_t2 < x.sd_t3) AS giam_3_thang,
        DATE_DIFF('month', a.opened_date, m.thang_cuoi)                AS thang_gan_bo,
        COALESCE(p.tong_phat, 0)                                       AS so_lan_bi_phat
    FROM silver_account a
    CROSS JOIN moc m
    LEFT JOIN hoat_dong_cuoi h USING (account_id)
    LEFT JOIN xu_huong x       USING (account_id)
    LEFT JOIN (SELECT account_id, SUM(n_penalty) AS tong_phat
               FROM fact_account_monthly GROUP BY 1) p USING (account_id)
)

SELECT
    account_id,
    thang_gd_cuoi                AS last_transaction_month,
    thang_im_lang                AS months_inactive,
    so_du_hien_tai               AS current_balance,
    giam_3_thang                 AS balance_declining_3m,
    thang_gan_bo                 AS tenure_months,
    so_lan_bi_phat               AS penalty_count,

    CASE
        WHEN thang_im_lang >= 6                      THEN '3. Ngủ đông'
        WHEN thang_im_lang >= 3 OR giam_3_thang      THEN '2. Cảnh báo'
        ELSE                                              '1. Hoạt động'
    END AS risk_segment,

    CASE
        WHEN so_du_hien_tai >= 100000 THEN '1. Rất cao (≥100k)'
        WHEN so_du_hien_tai >=  50000 THEN '2. Cao (50–100k)'
        WHEN so_du_hien_tai >=  20000 THEN '3. Trung bình (20–50k)'
        ELSE                               '4. Thấp (<20k)'
    END AS balance_tier,

    -- Vi sao tai khoan bi gan co canh bao.
    -- Hai ly do nay doi hoi hai cach xu ly hoan toan khac nhau:
    --   So du giam nhung VAN giao dich -> khach dang chuyen tien di noi khac,
    --      con lien lac duoc, con cuu duoc
    --   Ngung giao dich -> co the da bo di, chi phi keo ve cao
    -- Gop chung mot con so 215 se khien nguoi doc tuong tat ca deu sap mat.
    CASE
        WHEN thang_im_lang >= 3 THEN '2. Ngừng giao dịch'
        WHEN giam_3_thang       THEN '1. Số dư giảm 3 tháng'
        ELSE                         '0. Không có dấu hiệu'
    END AS risk_reason

FROM tong_hop;


-- ---------------------------------------------------------------------
-- dim_account — 4.500 tài khoản, kèm phân loại rủi ro
-- ---------------------------------------------------------------------
-- Gộp thuộc tính tĩnh (ngày mở, chi nhánh) với phân loại rủi ro tính được
-- ở trên. Cùng hạt 1 dòng/tài khoản nên phải nằm chung MỘT bảng — tách
-- làm hai dimension cùng khoá sẽ gây nhập nhằng khi lọc.
CREATE OR REPLACE TABLE dim_account AS
SELECT
    a.account_id,
    a.district_id,
    a.statement_frequency,
    a.opened_date,
    YEAR(a.opened_date) AS opened_year,
    r.last_transaction_month,
    r.months_inactive,
    r.current_balance,
    r.balance_declining_3m,
    r.tenure_months,
    r.penalty_count,
    r.risk_segment,
    r.balance_tier,
    r.risk_reason
FROM silver_account a
LEFT JOIN tinh_rui_ro r USING (account_id);
