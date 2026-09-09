# สคริปต์: Full_Dynamic_Occupancy.R
# รันโมเดล Occupancy 120 เดือน ร่วมกับปัจจัยแวดล้อม (Site Covariates) แบบเต็มรูปแบบ

library(unmarked)
library(dplyr)

# =========================================================
# 1. นำเข้าข้อมูลประวัติลาดตระเวน และ ปัจจัยแวดล้อม
# =========================================================
cat("1. กำลังโหลดข้อมูลประวัติลาดตระเวนและปัจจัยแวดล้อม...\n")
# 💡 สามารถเปลี่ยนชื่อไฟล์ตรงนี้ เพื่อวิเคราะห์ภัยคุกคามอื่นๆ (Logging, Land_E, NTFP) ได้เลย
dat_occ <- read.csv("D:/SMART_KUFF/Poaching_120M_Occupancy.csv")
dat_cov <- read.csv("D:/SMART_KUFF/Site_Covariates_HKK.csv")

# =========================================================
# 2. เตรียม Detection (Y) และ Effort (Observation Covs)
# =========================================================
cat("2. กำลังจัดเตรียมข้อมูล Y และ Effort...\n")
y_cols <- paste0("Visit_", 1:120)
y_matrix <- as.matrix(dat_occ[, y_cols])

eff_cols <- paste0("Effort_", 1:120)
eff_matrix <- as.matrix(dat_occ[, eff_cols])

# ปรับมาตรฐาน (Standardize) Effort ให้คำนวณง่ายขึ้น (ลดปัญหา Model Error)
eff_mean <- mean(eff_matrix, na.rm=TRUE)
eff_sd <- sd(eff_matrix, na.rm=TRUE)
eff_scaled <- (eff_matrix - eff_mean) / eff_sd

obs_covs <- list(Effort = eff_scaled)

# =========================================================
# 3. เตรียมปัจจัยแวดล้อม (Site Covariates) พร้อม Scale ค่า
# =========================================================
cat("3. กำลังปรับมาตรฐาน (Scale) ปัจจัยแวดล้อมพื้นที่...\n")
# การใช้ scale() สำคัญมากเมื่อหน่วยตัวแปรต่างกัน (ความสูงเป็นเมตร vs ระยะทางเป็น กม.)
site_covs <- data.frame(
  Elev      = scale(dat_cov$Elevation),
  Slope     = scale(dat_cov$Slope),
  Dist_Vill = scale(dat_cov$Dist_Village),
  Dist_Stat = scale(dat_cov$Dist_Station),
  Dist_Chk  = scale(dat_cov$Dist_Chkpt),
  Dist_Str  = scale(dat_cov$Dist_Stream)
)

# =========================================================
# 4. มัดรวมข้อมูลเข้า unmarkedMultFrame
# =========================================================
cat("4. กำลังจัดโครงสร้างข้อมูล Multi-Season (10 ปี)...\n")
umf_full <- unmarkedMultFrame(y = y_matrix,
                              siteCovs = site_covs,
                              obsCovs = obs_covs,
                              numPrimary = 10)

# =========================================================
# 5. รันโมเดล (Full Dynamic Occupancy Model)
# =========================================================
# สมมติฐานเชิงนิเวศวิทยาที่เราตั้งไว้:
# - psi (ความเสี่ยงปีแรก) : อิงจากความสูง (Elev) + ระยะห่างหมู่บ้าน (Dist_Vill)
# - gamma (อัตราการลาม) : อิงจากระยะห่างหมู่บ้าน (Dist_Vill)
# - epsilon (อัตราถอยร่น) : อิงจากระยะห่างจากหน่วยพิทักษ์ป่า (Dist_Stat)
# - p (โอกาสตรวจพบ) : อิงจากระยะทางเดินลาดตระเวน (Effort)
cat("5. กำลังรัน Full Model (อาจใช้เวลา 2-10 นาที กรุณารอสักครู่)...\n")
fm_full <- colext(psiformula = ~ Elev + Dist_Vill,
                  gammaformula = ~ Dist_Vill,
                  epsilonformula = ~ Dist_Stat,
                  pformula = ~ Effort,
                  data = umf_full)

# =========================================================
# 6. แสดงผลลัพธ์
# =========================================================
cat("\n==================================================\n")
cat("🎉 ประมวลผลเสร็จสมบูรณ์! นี่คือผลลัพธ์ของโมเดล:\n")
cat("==================================================\n")
print(summary(fm_full))
