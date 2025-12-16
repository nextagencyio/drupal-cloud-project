-- MySQL initialization script
-- This runs automatically when the MySQL container starts for the first time

-- Grant database creation and management permissions to drupal user
GRANT CREATE, DROP, ALTER, INDEX, REFERENCES ON *.* TO 'drupal'@'%';

-- Grant additional permissions needed for site management
GRANT CREATE USER, RELOAD ON *.* TO 'drupal'@'%';

-- Flush privileges to apply changes
FLUSH PRIVILEGES;

-- Log the permissions granted
SELECT 'Database permissions granted to drupal user' AS status;