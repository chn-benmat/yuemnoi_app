# Project Context: [Yuemnoi App]

## 1. Overview
- เป็นแอปพลิเคชันสำหรับจัดการการยืม-คืนอุปกรณ์

## 2. Tech Stack
- Language: TypeScript,Golang,Python
- Framework: Flutter
- Database: Supabase

## 3. Architecture & File Structure
- โฟลเดอร์ featuresจะเก็บฟีเจอร์ทั้งหมดที่เกี่ยวกับแอปพลิเคชัน
- ภายในโฟลเดอร์ data จะทำหน้าที่จัดการและแปลงข้อมูลดิบจาก API และ Local Storage
    - โฟลเดอร์ datasource ตัวเชื่อมต่อและดึงข้อมูลดิบจากแหล่งภายนอกโดยตรง (แบ่งเป็น Remote และ Local)
    - โฟลเดอร์ model โครงสร้างข้อมูล (DTO) ที่แมปตามหน้าตาของ API หรือ Database พร้อมทำหน้าที่แปลงตัวเองให้เป็น Entity (toEntity()) ก่อนส่งต่อ
    - โฟลเดอร์ repository เป็นการ Implementation ของ Repository Interface จากชั้น Domain ทำหน้าที่คุม Logic การเลือกใช้ Data Source (เช่น การทำ Cache ข้อมูล) และส่งข้อมูลกลับไปให้ Domain ในรูปแบบของ Entity
- โฟลเดอร์ domain ที่เป็นหัวใจหลักของฟีเจอร์ (Core Business Logic) จะไม่มีการขึ้นตรงหรือผูกมัดกับ Framework, Database หรือ Libraryภายนอกใดๆทั้งสิ้น
    - โฟลเดอร์ entity เก็บ Object โครงสร้างข้อมูลและกฎทางธุรกิจพื้นฐาน (Core Business Rules) ของฟีเจอร์นั้นๆ
    - โฟลเดอร์ repository นิยามอินเตอร์เฟส (Interface/Contract) เพื่อกำหนดว่าระบบต้องการจัดการอะไรกับข้อมูลบ้าง (เช่น บันทึก, ดึงข้อมูล) โดยจะส่งต่อหน้าที่นี้ให้ Data Layer เป็นคนไปดึงข้อมูลจริงกลับมาให้
    - โฟลเดอร์ usecase ตัวควบคุมขั้นตอนการทำงานหลักของแอปพลิเคชัน (Application Business Logic) ทำหน้าที่รับข้อมูลจาก Presentation Layer มาประมวลผลร่วมกับ Entity และสั่งการทำงานต่างๆ ให้เป็นไปตามเงื่อนไขของระบบ
- ภายในโฟลเดอร์ presentation จะเก็บ ui ทั้งหมดที่เกี่ยวกับแอปพลิเคชัน และเป็นส่วนที่ผู้ใช้โต้ตอบด้วยโดยตรง
    - แยก widget ที่ใช้บ่อยๆจัดเก็บไว้ในโฟลเดอร์ widgets เพื่อนำมาใช้ซ้ำ
    - โฟลเดอร์ pages เอาไว้แสดงหน้าเว็บแต่ละหน้า
- ภายในโฟลเดอร์ coreจะเก็บ core function ที่ใช้ร่วมกัน
- ภาพที่จะใช้สำหรับทำ UI อยู่ใน ไฟร์ assets/images

## 4. Development Rules
- เวลาcommentให้เป็นภาษาไทยอธิบายเข้าใจง่าย

## 5. Current Status & Next Steps
- ในตอนนี้จะทำเพียงแต่ frontend ไปก่อน โดยใช้ภาษาDart และ Framework Flutter
- ตอนนี้ทำส่วนหน้าบ้านของฟีเจอร์ authentication เสร็จแล้ว
