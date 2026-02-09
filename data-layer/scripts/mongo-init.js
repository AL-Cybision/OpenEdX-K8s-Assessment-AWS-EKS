// Replace placeholders before running
const dbName = "openedx";
const adminUser = "admin";
const adminPwd = "<ADMIN_PASSWORD>";
const appUser = "openedx";
const appPwd = "<APP_PASSWORD>";

db = db.getSiblingDB("admin");
db.createUser({
  user: adminUser,
  pwd: adminPwd,
  roles: [{ role: "root", db: "admin" }]
});

db = db.getSiblingDB(dbName);
db.createUser({
  user: appUser,
  pwd: appPwd,
  roles: [{ role: "readWrite", db: dbName }]
});
