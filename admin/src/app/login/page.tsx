"use client";
import { useState } from "react";
import { LockKeyhole, ArrowRight, LoaderCircle } from "lucide-react";
export default function Login() {
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const form = new FormData(e.currentTarget);
    try {
      const res = await fetch("/api/session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: form.get("email"),
          password: form.get("password"),
        }),
      });
      const data = await res.json();
      if (!res.ok) throw Error(data.error);
      window.location.assign("/overview");
    } catch (err) {
      setError(err instanceof Error ? err.message : "ไม่สามารถเข้าสู่ระบบได้");
      setBusy(false);
    }
  }
  return (
    <main className="login">
      <div className="login-brand">
        <img src="/brand.png" alt="ยืมหน่อย" />
        <h1>
          พื้นที่ดูแล
          <br />
          ทุกการแบ่งปัน
        </h1>
        <p>จัดการแอป ดูภาพรวม และดูแลชุมชนยืมหน่อย</p>
      </div>
      <form className="login-form" onSubmit={submit}>
        <span className="icon-tile">
          <LockKeyhole />
        </span>
        <h2>เข้าสู่ระบบเจ้าหน้าที่</h2>
        <p className="muted">ใช้บัญชีที่ได้รับสิทธิ์จากผู้ดูแลระบบ</p>
        <label>
          อีเมล
          <input
            name="email"
            type="email"
            required
            autoComplete="username"
            placeholder="you@example.com"
          />
        </label>
        <label>
          รหัสผ่าน
          <input
            name="password"
            type="password"
            required
            minLength={6}
            autoComplete="current-password"
            placeholder="กรอกรหัสผ่าน"
          />
        </label>
        {error && (
          <p role="alert" className="error">
            {error}
          </p>
        )}
        <button className="primary" disabled={busy}>
          {busy ? <LoaderCircle className="spin" /> : <ArrowRight />}เข้าสู่ระบบ
        </button>
        <small className="muted">
          การเข้าถึงข้อมูลและการดำเนินงานของเจ้าหน้าที่จะถูกบันทึก
        </small>
      </form>
    </main>
  );
}
