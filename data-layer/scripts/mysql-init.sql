-- Replace placeholders before running
CREATE DATABASE IF NOT EXISTS openedx;
CREATE USER IF NOT EXISTS 'openedx'@'%' IDENTIFIED BY '<PASSWORD>';
GRANT ALL PRIVILEGES ON openedx.* TO 'openedx'@'%';
FLUSH PRIVILEGES;
