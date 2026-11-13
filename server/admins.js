// Manage who can use the admin ticket page (/admin).
//   node admins.js                 list admins
//   node admins.js add <username>  make a game account an admin
//   node admins.js remove <username>
// (On the Droplet: docker compose exec game node server/admins.js add <username>)
const accounts = require("./accounts");

const [cmd, name] = process.argv.slice(2);
if ((cmd === "add" || cmd === "remove") && name) {
  if (accounts.setAdmin(name, cmd === "add")) {
    console.log(cmd === "add" ? `${name} is now an admin. Log in at /admin with that game account.` : `${name} is no longer an admin.`);
  } else {
    console.log(`No account called "${name}". Create it in the game first (Sign Up), then run this again.`);
    process.exitCode = 1;
  }
} else {
  const list = accounts.listAdmins();
  console.log(list.length ? "Admins:\n" + list.map((a) => `  ${a.username}  ${a.email || ""}`).join("\n") : "No admins yet. Add one: node admins.js add <username>");
}
