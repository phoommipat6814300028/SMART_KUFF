<<<<<<< HEAD
\# HKK Patrol Optimization Project

=======
# 🌳 Huai Kha Khaeng (HKK) Wildlife Sanctuary Patrol Optimization

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

โปรเจกต์นี้เป็นการพัฒนาระบบคาดการณ์พื้นที่เสี่ยงต่อการลักลอบล่าสัตว์และตัดไม้ทำลายป่า ในเขตรักษาพันธุ์สัตว์ป่าห้วยขาแข้ง โดยผสานรวมการประมวลผลภาพถ่ายดาวเทียมด้วยปัญญาประดิษฐ์ (AI - BigEarthNet) เข้ากับการวิเคราะห์การเข้าถึงพื้นที่ (Accessibility / Cost-Surface) เพื่อนำไปป้อนเข้าสู่แบบจำลอง Occupancy Model สำหรับวางแผนการลาดตระเวนของเจ้าหน้าที่

## 📑 สถาปัตยกรรมของโปรเจกต์ (Project Overview)
โปรเจกต์นี้แบ่งการทำงานออกเป็น 2 ส่วนหลัก:
1. **Satellite & AI Pipeline (BigEarthNet):** ดึงข้อมูล Sentinel-1 & 2 รายเดือน มาสกัดลักษณะเด่น (Deep Embeddings) ขนาด 2,048 มิติด้วย ResNet50 และลดขนาดข้อมูล (PCA) เหลือ 3-4 ตัวแปรสำหรับแต่ละตารางกริด (1km x 1km)
2. **Accessibility & Threat-Access Model:** คำนวณความยากง่ายในการเข้าถึงพื้นที่ (Cost/Resistance Surface) โดยใช้ข้อมูลความชัน (DEM) และสมการ Tobler's hiking function ร่วมกับการวิเคราะห์ Randomized Shortest Paths (RSP) ด้วยแพ็กเกจ `ConScape.jl` 

---

## 📂 โครงสร้างโฟลเดอร์ (Directory Structure)

```text
HKK_Patrol_Optimization/
│
├── Data/                       # โฟลเดอร์เก็บข้อมูล (ระบุใน .gitignore เพื่อไม่ให้อัปโหลดไฟล์ขนาดใหญ่)
│   ├── raw/                    # ข้อมูลดิบ (Sentinel-1/2, FABDEM, OSM Roads)
│   ├── interim/                # ข้อมูลระหว่างการประมวลผล (เช่น ภาพที่ผ่านการต่อ/Crop)
│   └── raster/                 # ไฟล์ผลลัพธ์ (เช่น Resistance_100m.tif, Accessibility_RSP_stack.tif)
│
├── Scripts/                    # โฟลเดอร์เก็บสคริปต์สำหรับประมวลผล
│   ├── 01_satellite_pipeline.py # สคริปต์ดึงข้อมูล Sentinel และเตรียมภาพ
│   ├── 02_bigearthnet_pca.py    # สคริปต์ดึง Deep Embeddings และทำ PCA
│   ├── calculate_accessibility.R # สคริปต์ R (ใช้ ConScapeR) สำหรับสร้าง Threat-Access Raster
│   └── occupancy_model.R        # สคริปต์สร้างแบบจำลองคาดการณ์ความเสี่ยงขั้นสุดท้าย
│
├── Doc/                        # เอกสารอ้างอิงและคู่มือ
│   ├── Proposal_Method.docx
│   └── methods_description.pdf
│
├── .gitignore                  # ไฟล์ละเว้นการอัปโหลดข้อมูลดิบและไฟล์ชั่วคราว
└── README.md                   # ไฟล์นี้
```

---

## 🛠️ ข้อกำหนดเบื้องต้น (Prerequisites)

เนื่องจากโปรเจกต์นี้มีการใช้เครื่องมือหลายภาษา คุณจำเป็นต้องติดตั้งโปรแกรมต่อไปนี้:
* **Python 3.8+**: สำหรับการดึงข้อมูลดาวเทียมและรันโมเดล Deep Learning (PyTorch, Rasterio, Scikit-learn)
* **R 4.0+**: สำหรับการจัดการข้อมูลเชิงพื้นที่และการรันแบบจำลอง Occupancy (แพ็กเกจ `terra`, `sf`, `gdistance`)
* **Julia**: จำเป็นสำหรับการคำนวณ Randomized Shortest Paths ขนาดใหญ่ผ่าน `ConScape.jl` (เข้าถึงผ่าน `ConScapeR` ใน R)

---

## 📥 ข้อมูลที่ต้องใช้ (Required Datasets)
**ห้ามอัปโหลดข้อมูลเหล่านี้ลง GitHub เนื่องจากมีขนาดใหญ่ (ตั้งค่าไว้แล้วใน `.gitignore`)**

1. **ภาพถ่ายดาวเทียม:** Sentinel-1 และ Sentinel-2 (ภาพ composite รายเดือน)
2. **ระดับความสูง (DEM):** FABDEM (bare-earth Copernicus GLO-30) ความละเอียด 30m
3. **เส้นทาง (Roads):** OpenStreetMap (OSM) ประเภท `highway=*` 
4. **ข้อมูลประวัติการลาดตระเวน:** Historical patrol data เพื่อใช้เป็นตัวแปร X_ik ใน Occupancy Model
5. **กริดและหน้ากากพื้นที่:** 
   - ขอบเขตพื้นที่อนุรักษ์ (Protected-area boundary)
   - ไฟล์ต้นแบบ `Risk_Surface.asc` ขนาด 1km

---

## 🚀 ขั้นตอนการรันโปรเจกต์ (Workflow)

**Step 1: การเตรียมข้อมูลทางภูมิประเทศและการเข้าถึง (Accessibility)**
รันสคริปต์เพื่อสร้าง Cost Surface จาก DEM และคำนวณการเข้าถึงพื้นที่จากถนนด้วย 5 ค่า Theta ($0.01$ ถึง $100$)
```bash
Rscript Scripts/calculate_accessibility.R
```
*ผลลัพธ์ที่ได้:* `Data/raster/Accessibility_RSP_stack.tif`

**Step 2: การประมวลผลภาพถ่ายดาวเทียมด้วย AI**
เตรียมภาพ Sentinel รายเดือนและดึงลักษณะทางกายภาพผ่าน BigEarthNet 
```bash
python Scripts/01_satellite_pipeline.py
python Scripts/02_bigearthnet_pca.py
```
*ผลลัพธ์ที่ได้:* ไฟล์ CSV หรือ Raster ขององค์ประกอบหลัก (PCA Components) 3-4 ตัวแปรต่อกริด

**Step 3: การรันแบบจำลอง Occupancy**
นำข้อมูล PCA Components, ตัวแปรการเข้าถึงพื้นที่ (Accessibility) และประวัติการลาดตระเวนมารวมกัน
```bash
Rscript Scripts/occupancy_model.R
```

---

## 💡 หมายเหตุสำหรับ Contributor
- หากต้องการอัปเดตโมเดล ให้ปรับแก้ในโฟลเดอร์ `Scripts/`
- โปรดตรวจสอบให้แน่ใจว่าไม่ได้ push ไฟล์นามสกุล `.tif`, `.nc`, `.asc` หรือ `.SAFE` ขึ้น repository
>>>>>>> 1ef8e7b443eeb231d44956be8d8e990a189d5412


graph TD
    %% การกำหนดสีให้แผนภาพ
    classDef rawData fill:#f9f6f0,stroke:#333,stroke-width:2px;
    classDef script fill:#d4e6f1,stroke:#2874a6,stroke-width:2px,stroke-dasharray: 5 5;
    classDef output fill:#d5f5e3,stroke:#239b56,stroke-width:2px;
    classDef final fill:#fadbd8,stroke:#c0392b,stroke-width:3px;

    %% ---------------------------------------------------
    %% สายที่ 1: AI Pipeline
    subgraph "1. การหาพื้นที่เสี่ยง (AI & Risk)"
        A1(ภาพดาวเทียม Sentinel) ::: rawData --> S1[hkk_bigearthnet_extraction.py] ::: script
        S1 -->|AI สกัดลักษณะพื้นที่ด้วย ResNet50 & PCA| O1(ข้อมูลสภาพแวดล้อมเชิงลึก) ::: output
        O1 -.->|นำมาประเมินร่วมกับข้อมูลลาดตระเวน| O1_2(Risk_Surface.asc) ::: output
    end

    %% ---------------------------------------------------
    %% สายที่ 2: Accessibility Pipeline
    subgraph "2. ความยากลำบากในการเดินป่า (Accessibility)"
        A2(ข้อมูลความสูง FABDEM) ::: rawData --> S2[Prepare_DEM_Slope_Tobler.py] ::: script
        S2 -->|สมการความเร็วการเดิน Tobler| O2(แผนที่ความเร็วเดินป่า) ::: output
        
        A3(ข้อมูลถนน OSM) ::: rawData --> S3_1[Import_OSM_Roads.py] ::: script
        S3_1 --> S3_2[Rasterize_OSM_Roads.py] ::: script
        S3_2 --> O3(แผนที่จุดเริ่มต้นจากถนน) ::: output

        O2 --> S4[calculate_accessibility.R] ::: script
        O3 --> S4
        S4 -->|รันโปรแกรม ConScape.jl| O4(Accessibility_RSP_stack.tif) ::: output
    end

    %% ---------------------------------------------------
    %% สายที่ 3: Optimization Pipeline
    subgraph "3. การสร้างเส้นทาง (Routing)"
        A4(แผนที่ขอบเขตพื้นที่) ::: rawData --> S5[Route_Generation.py] ::: script
        S5 -->|สุ่มสร้างเส้นทางจำลองนับหมื่นเส้น| O5(โฟลเดอร์ Routes/*.tif) ::: output
        O5 --> S6[Create_Route_Matrix_from_tif.R] ::: script
        S6 -->|แปลงเส้นทางเป็น Sparse Matrix| O6(HKK_Route_Matrix.rds) ::: output
    end

    %% ---------------------------------------------------
    %% บทสรุป: รวมข้อมูลเข้าด้วยกัน
    O1_2 -->|ส่งข้อมูลพื้นที่เสี่ยง| S7[Prelim_Optimization.R] ::: script
    O6 -->|ส่งข้อมูลตัวเลือกเส้นทางทั้งหมด| S7
    
    S7 -->|ตัวแก้สมการ Gurobi ตัดสินใจเลือกเส้นทาง| F1((Integer_Patrol_Frequency.tif\nแผนที่ชี้เป้าความถี่ในการเดินป่า)) ::: final
    S7 -->|คำนวณความเสี่ยงที่เหลือ| F2((Residual_Risk.tif\nแผนที่ความเสี่ยงคงเหลือ)) ::: final
