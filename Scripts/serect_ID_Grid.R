# สคริปต์เสริม: เพิ่มคอลัมน์ Grid_ID ให้กับตารางแผนที่
library(sf)
library(dplyr)

# 1. โหลดไฟล์ Grid ต้นฉบับ (ใช้ชื่อที่มี _ ตามที่เราแก้กันไปครับ)
grid_file <- "D:/SMART_KUFF/Grid_HKK_.shp"
grid_sf <- st_read(grid_file)

# 2. สร้างคอลัมน์ใหม่ชื่อ Grid_ID รันตัวเลขตั้งแต่ 1 ถึงจำนวนกริดทั้งหมด
grid_sf <- grid_sf %>%
  mutate(Grid_ID = row_number())

# 3. เซฟเป็นไฟล์ใหม่ชื่อ Grid_HKK_ID.shp
out_file <- "D:/SMART_KUFF/Grid_HKK_ID.shp"
st_write(grid_sf, out_file, delete_layer = TRUE)

cat("เพิ่ม Grid_ID สำเร็จ! บันทึกไฟล์ใหม่เรียบร้อยแล้วครับ\n")
