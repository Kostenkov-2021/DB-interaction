CREATE DATABASE IF NOT EXISTS idz2;

SELECT
    currentUser() AS current_user,
    currentDatabase() AS current_database,
    version() AS clickhouse_version;
