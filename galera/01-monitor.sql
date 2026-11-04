CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED BY 'monitorpass';
GRANT USAGE ON *.* TO 'monitor'@'%';
GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'%';
GRANT SELECT ON *.* TO 'monitor'@'%';
FLUSH PRIVILEGES;
