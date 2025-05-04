# pgcontainer-backup
This Bash script automates the process of backing up a **PostgreSQL** database running inside a **Docker container**. It includes safety mechanisms such as lock files to prevent concurrent backups, and optionally supports verbose logging and SHA256 checksums.

---

## 📦 Features

* Backs up PostgreSQL databases from Docker containers
* Uses `pg_basebackup` inside the container for a full physical backup
* Optional SHA256 checksum generation for data integrity verification
* Verbose logging support

---

## 🚀 Usage

```bash
bash <(curl -s https://raw.githubusercontent.com/nxyzo/pgcontainer-backup/refs/heads/main/pgcontainer-backup.sh)

./pgcontainer-backup.sh [OPTIONS]
```

### Required Parameters

| Option                | Description                                                    |
| --------------------- | -------------------------------------------------------------- |
| `-n`, `--name`        | **(Required)** Name of the Docker container running PostgreSQL |
| `-d`, `--destination` | **(Required)** Host directory where backups will be stored     |
| `-u`, `--pg-user`     | **(Required)** PostgreSQL username                             |
| `-p`, `--pg-password` | **(Required)** PostgreSQL password                             |

### Optional Flags

| Option                    | Description                                  |
| ------------------------- | -------------------------------------------- |
| `-v`, `--verbose`         | Show detailed logs during the backup process |
| `-c`, `--create-checksum` | Generate SHA256 checksum for backup          |
| `-h`, `--help`            | Show help message and exit                   |

---

## 🧪 Example

```bash
./backup.sh \
  --name postgres_container \
  --destination /mnt/backups \
  --pg-user postgres \
  --pg-password secret \
  --verbose \
  --create-checksum
```

---

## 📁 Backup Output Structure

Each backup is stored in a subfolder named like:

```
pg_<container_name>_YYYY-MM-DD_HH-MM-SS/
```

If checksum is enabled, a `checksum.sha256` file is also created in this folder:

```
pg_<container_name>_YYYY-MM-DD_HH-MM-SS_full/
```

---

## 🔐 Safety Measures

* A lock file `/tmp/backup.lock` is created inside the container to prevent parallel backup jobs.
* If Docker is not running, the script attempts to start the Docker daemon automatically.
* All temporary folders inside the container are cleaned after the process.

---

## ✅ Requirements

* **Docker** (version 28.x required)
* A running **PostgreSQL Docker container**
* The user must have permission to execute Docker commands

---

## 🔧 Notes

* This script uses `pg_basebackup` and assumes your PostgreSQL container has the necessary tools installed.
* Do **not** forget to set proper backup directory permissions if running as root or from a cron job.
* The script is designed to be run from a host system, **not inside the container**.

* To properly back up the database, you need a dedicated backup user in the PostgreSQL container. You can create the user as follows:

```sql
CREATE ROLE backup_user WITH REPLICATION LOGIN PASSWORD 'deinPasswort';
```

---

## 🛠 Development To-Do

* Add support for retention/rotation policies
* Integrate email, discord or Slack notifications on backup success/failure
* Add logging to file for long-term auditability
* Add backup encryption
* Copy backup to remote location

---