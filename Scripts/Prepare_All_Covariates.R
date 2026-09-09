# สคริปต์: Prepare_All_Covariates.R
# หน้าที่: สกัดค่าภูมิประเทศ (DEM/Slope) และวัดระยะทาง (Distance) สู่ตัวแปรต่างๆ

library(raster)
library(sf)
library(dplyr)

# =========================================================
# 1. โหลดข้อมูลแม่แบบ กริด 1x1 กิโลเมตร
# =========================================================
cat("1. กำลังโหลด Grid แม่แบบ...\n")
grid <- st_read("D:/SMART_KUFF/Grid_HKK_.shp", quiet = TRUE)

# 🌟 เพิ่มบรรทัดนี้: กำหนดระบบพิกัด (CRS) เป็น UTM Zone 47N (รหัส 32647)
st_crs(grid) <- 32647

grid_cents <- st_centroid(grid) # สร้างจุดกึ่งกลางกริดเพื่อใช้วัดระยะทางาง

# =========================================================
# 2. จัดการข้อมูลภูมิประเทศ (Elevation & Slope)
# =========================================================
cat("2. กำลังสกัดค่าความสูงและความลาดชัน...\n")
dem <- raster("D:/SMART_KUFF/Covariates/DEM30.tif")
slope <- terrain(dem, opt = "slope", unit = "degrees")

# ดึงค่าลงตารางกริด
grid$Elevation <- raster::extract(dem, grid_cents)
grid$Slope <- raster::extract(slope, grid_cents)

# =========================================================
# 3. โหลดข้อมูลปัจจัยแวดล้อมอื่นๆ (Shapefiles)
# =========================================================
cat("3. กำลังโหลดแผนที่จุดและเส้น...\n")
# ใช้ st_transform เพื่อบังคับให้พิกัดตรงกับ Grid ป้องกัน Error
chkpt   <- st_transform(st_read("D:/SMART_KUFF/Covariates/HKK_checkpoint.shp", quiet=TRUE), st_crs(grid))
stream  <- st_transform(st_read("D:/SMART_KUFF/Covariates/HKK_stream.shp", quiet=TRUE), st_crs(grid))
village <- st_transform(st_read("D:/SMART_KUFF/Covariates/HKK_Village.shp", quiet=TRUE), st_crs(grid))
station <- st_transform(st_read("D:/SMART_KUFF/Covariates/HKK_wilflifestation.shp", quiet=TRUE), st_crs(grid))
# (พิมพ์ชื่อ wilflifestation ตามไฟล์ในภาพเป๊ะๆ)

# =========================================================
# 4. คำนวณระยะทาง (ระยะทางที่สั้นที่สุดจากจุดกึ่งกลางกริด)
# =========================================================
cat("4. กำลังคำนวณระยะทาง (ขั้นตอนนี้อาจใช้เวลา 1-3 นาที)...\n")

# วัดระยะและแปลงหน่วยเป็น "กิโลเมตร" (หาร 1000) เพื่อให้โมเดลสถิติทำงานได้ดีขึ้น
grid$Dist_Chkpt   <- as.numeric(apply(st_distance(grid_cents, chkpt), 1, min)) / 1000
grid$Dist_Stream  <- as.numeric(apply(st_distance(grid_cents, stream), 1, min)) / 1000
grid$Dist_Village <- as.numeric(apply(st_distance(grid_cents, village), 1, min)) / 1000
grid$Dist_Station <- as.numeric(apply(st_distance(grid_cents, station), 1, min)) / 1000

# =========================================================
# 5. ส่งออกข้อมูลเป็นตาราง (CSV)
# =========================================================
cat("5. กำลังบันทึกไฟล์ผลลัพธ์...\n")
# ตัดเอาเฉพาะคอลัมน์ตัวแปรที่ต้องการ
site_covs <- st_drop_geometry(grid) %>%
  dplyr::select(Elevation, Slope, Dist_Chkpt, Dist_Stream, Dist_Village, Dist_Station)

out_file <- "D:/SMART_KUFF/Site_Covariates_HKK.csv"
write.csv(site_covs, out_file, row.names = FALSE)

cat("==================================================\n")
cat("🎉 เสร็จสมบูรณ์! บันทึกไฟล์เรียบร้อยที่:\n", out_file, "\n")
cat("==================================================\n")
