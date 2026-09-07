# สคริปต์: Prepare_120M_Occupancy.R
# หน้าที่: เตรียมข้อมูล Occupancy Model ระยะยาว 10 ปี (120 เดือน)
# รองรับการเปลี่ยนประเภทภัยคุกคาม (Logging, Poaching, Land_E, NTFP)

library(raster)
library(sf)
library(dplyr)
library(lubridate)

# =========================================================
# 1. ตั้งค่า Path ข้อมูล (ตามโครงสร้างในเครื่อง D:\SMART_KUFF)
# =========================================================
dir_effort <- "D:/SMART_KUFF/N_patrol/Effort_All"
file_grid  <- "D:/SMART_KUFF/grid_HKK.shp"

# **เปลี่ยนชื่อไฟล์ตรงนี้ เพื่อวิเคราะห์ภัยคุกคามประเภทอื่น**
# ตัวเลือก: Logging_2016-2025.shp, Poching_2016-2025.shp, 
# Land_E_2016-2025.shp, NTFP_2016-2025.shp
file_threat <- "D:/SMART_KUFF/Threat/Poching_2016-2025.shp" 

# =========================================================
# 2. โหลดแม่แบบ Grid และข้อมูล Patrol Effort (120 ไฟล์)
# =========================================================
cat("กำลังโหลดข้อมูล Grid และ Patrol Effort ทั้งหมด 120 เดือน...\n")
grid_hkk <- st_read(file_grid, quiet = TRUE)

# ดึงชื่อไฟล์ .asc ทั้งหมด 120 ไฟล์ และเรียงตามลำดับเวลาให้ถูกต้อง
effort_files <- list.files(dir_effort, pattern = "\\.asc$", full.names = TRUE)
effort_files <- sort(effort_files) # สำคัญมาก! เพื่อให้เดือนเรียงจาก 1 ถึง 120

if(length(effort_files) != 120) {
  warning(paste("พบไฟล์ Effort จำนวน", length(effort_files), "ไฟล์ (คาดหวัง 120 ไฟล์)"))
}

effort_stack <- stack(effort_files)
names(effort_stack) <- paste0("Effort_", 1:length(effort_files))

# =========================================================
# 3. โหลดและจัดการข้อมูลจุดคุกคาม (10 ปี)
# =========================================================
cat("กำลังจัดกลุ่มจุดภัยคุกคามรายเดือน และประยุกต์ใช้กฎเหล็ก Occupancy (NA)...\n")
threat_sf <- st_read(file_threat, quiet = TRUE)

# *** จุดที่ต้องตรวจสอบ ***
# เปลี่ยน "Date_Col" เป็นชื่อคอลัมน์ที่เก็บ 'วันที่' หรือ 'ปี-เดือน' ในไฟล์ .shp ของคุณ
# สมมติว่าไฟล์ของคุณมีคอลัมน์ชื่อ "Date" (รูปแบบ YYYY-MM-DD)
date_column <- "Date" 

# สร้างคอลัมน์ ปี-เดือน (เช่น "2016-01") เพื่อใช้กรองข้อมูล
threat_sf$YearMonth <- format(as.Date(threat_sf[[date_column]]), "%Y-%m")

# =========================================================
# 4. วนลูป 120 เดือน เพื่อซ้อนทับจุดกับ Grid และจัดหน้าตาตาราง
# =========================================================
det_list <- list()

# สร้างลำดับ ปี-เดือน 120 เดือน (ม.ค. 2016 ถึง ธ.ค. 2025)
month_seq <- seq(as.Date("2016-01-01"), as.Date("2025-12-01"), by = "month")
ym_labels <- format(month_seq, "%Y-%m")

for(i in 1:length(ym_labels)) {
  ym <- ym_labels[i]
  
  # กรองเฉพาะจุดภัยคุกคามของเดือนนั้นๆ
  pts_month <- threat_sf %>% filter(YearMonth == ym)
  
  # ถ้าเดือนนั้นไม่มีภัยคุกคามเลย สร้าง Raster 0 ขึ้นมา
  if(nrow(pts_month) == 0) {
    det_rst <- effort_stack[[i]]
    det_rst[] <- 0
  } else {
    # ถ้ามี ให้ประยุกต์ใช้หลักการนับจุดคล้าย raster_point_count.r
    pts_sp <- as(pts_month, "Spatial")
    count_rst <- rasterize(pts_sp, effort_stack[[i]], fun = function(x, ...) length(x), background = 0)
    
    # แปลงเป็น Dummy Variable (เจอ = 1, ไม่เจอ = 0) เหมือน dummy_raster.r
    det_rst <- count_rst
    det_rst[det_rst > 0] <- 1
  }
  
  # ประยุกต์กฎเหล็ก Occupancy: ถ้า Effort เป็น 0 หรือ NA ให้ความเสี่ยงเป็น NA
  eff_rst <- effort_stack[[i]]
  det_rst[eff_rst == 0 | is.na(eff_rst)] <- NA
  
  names(det_rst) <- paste0("Visit_", i)
  det_list[[i]] <- det_rst
}

det_stack <- stack(det_list)

# =========================================================
# 5. รวมเป็น DataFrame พร้อมใช้งาน
# =========================================================
cat("กำลังรวมร่างข้อมูล 120 เดือน เป็น Data Frame...\n")
df_effort <- as.data.frame(effort_stack, xy = TRUE)
df_det <- as.data.frame(det_stack, xy = FALSE)

Final_120M_Data <- cbind(df_effort, df_det)

# บันทึกผลลัพธ์
out_file <- "D:/SMART_KUFF/Poaching_120M_Occupancy.csv"
write.csv(Final_120M_Data, out_file, row.names = FALSE)
cat(paste("เสร็จสมบูรณ์! บันทึกไฟล์ที่:", out_file, "\n"))