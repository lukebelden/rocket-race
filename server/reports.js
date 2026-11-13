// Read player problem reports (tickets) from the database. The admin page at /admin is
// the easier way; this is handy over SSH.
//   node reports.js            new tickets
//   node reports.js all        every ticket
//   node reports.js done 12    mark ticket #12 as resolved
// (On the Droplet: docker compose exec game node server/reports.js)
const accounts = require("./accounts");

const [cmd, id] = process.argv.slice(2);
if (cmd === "done" && id) {
  accounts.setReportStatus(id, "done");
  console.log(`Report #${id} marked as done.`);
} else {
  const rows = accounts.listReports(cmd === "all" ? "all" : "new");
  if (rows.length === 0) console.log("No reports.");
  for (const r of rows) {
    console.log(`#${r.id}  ${new Date(r.created_at).toISOString().slice(0, 16).replace("T", " ")}  [${r.category}]  from ${r.username}` +
      (r.target ? `  about ${r.target}` : "") + `  (${r.status})\n    ${r.message.replace(/\n/g, "\n    ")}\n    ${r.platform || ""}\n`);
  }
}
