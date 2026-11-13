// Sends email (password reset codes, problem reports) through any SMTP provider - for example
// Resend, SendGrid, Mailgun, Postmark, or Gmail with an app password.
//
// Configure with environment variables:
//   SMTP_HOST, SMTP_PORT (default 587), SMTP_USER, SMTP_PASS, MAIL_FROM ("Rocket Race <no-reply@...>")
//   REPORT_EMAIL   optional: where new problem reports are forwarded
//
// Without SMTP_HOST (e.g. when testing locally) nothing is sent: the message is printed in
// the server console instead, so reset codes can still be tested.

const nodemailer = require("nodemailer");

const HOST = process.env.SMTP_HOST || "";
const FROM = process.env.MAIL_FROM || "Rocket Race <no-reply@rocket-race.local>";
const REPORT_EMAIL = process.env.REPORT_EMAIL || "";

const transport = HOST
  ? nodemailer.createTransport({
      host: HOST,
      port: Number(process.env.SMTP_PORT) || 587,
      secure: Number(process.env.SMTP_PORT) === 465,
      auth: process.env.SMTP_USER ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS || "" } : undefined,
    })
  : null;

async function send(to, subject, text) {
  if (!transport) {
    console.log(`[mail - not sent, SMTP not configured]\n  To: ${to}\n  Subject: ${subject}\n  ${text.replace(/\n/g, "\n  ")}`);
    return true;
  }
  try {
    await transport.sendMail({ from: FROM, to, subject, text });
    return true;
  } catch (err) {
    console.error("Email failed:", err.message);
    return false;
  }
}

function sendResetCode(to, username, code) {
  return send(
    to,
    "Your Rocket Race password reset code",
    `Hi ${username},\n\nYour password reset code is: ${code}\n\n` +
      "Type it into the game with your new password. It works for 15 minutes.\n" +
      "If you didn't ask for this, you can ignore this email - your password hasn't changed.\n\n- Rocket Race"
  );
}

function forwardReport(report) {
  if (!REPORT_EMAIL) return;
  send(
    REPORT_EMAIL,
    `[Rocket Race] New ${report.category} report #${report.id}`,
    `From: ${report.username}\nCategory: ${report.category}\n` +
      (report.target ? `About player: ${report.target}\n` : "") +
      `Platform: ${report.platform}\n\n${report.message}`
  );
}

module.exports = { sendResetCode, forwardReport, configured: !!transport };
