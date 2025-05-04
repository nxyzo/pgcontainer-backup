#!/bin/bash
# filepath: ./pgcontainer-backup.sh

# Define color variables
YELLOW="\e[33m"
RED="\e[31m"
GREEN="\e[32m"
BLUE="\e[34m"
PURPLE="\e[35m"
RESET="\e[0m"


###
### ---Funtional variables -DO NOT CHANGE ANYTHING HERE---
###

timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
verbose=false
checksum=false
backup_lock_file_exists="false"
backup_output_folder_name=""

###
### ---Variables---
###

# setup that a few vars are absolutly needed and must be set by user
containerName=""    #set by user
backupDirectory=""  #set by user
postgres_user=""     #set by user backup_user
postgres_password=""        #set by user 1234
container_backup_lock_file_path="/tmp/backup.lock"
container_tmp_backup_folder="/tmp"

###
### ---FUNCTIONS---
### 

function parse_parameters() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -n|--name)
                containerName="$2"
                shift 2
                ;;
            -d|--destination)
                backupDirectory="$2"
                shift 2
                ;;
            -u|--pg-user)
                postgres_user="$2"
                shift 2
                ;;
            -p|--pg-password)
                postgres_password="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift 1
                ;;
            -c|--create-checksum)
                checksum=true
                shift 1
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown parameter: $1"
                exit 1
                ;;
        esac
    done
}

show_help() {
    echo -e "
${GREEN}Usage:${RESET} $0 [options]

Options:
  -n, --name <container_name>      (Required) Name of the Docker container running the PostgreSQL database.
  -d, --destination <path>         (Required) Destination directory on the host where the backup will be stored.
  -u, --pg-user <username>         (Required) PostgreSQL username for the backup process.
  -p, --pg-password <password>     (Required) PostgreSQL password for the backup process.
  -v, --verbose                    Show all logs during the backup process.
  -c, --checksum                   Enable checksum generation (e.g., SHA256) for the backup file.
  -h, --help                       Show this help message and exit.

Example:
  $0 -n postgres_container -d /backups -u postgres -p secretpassword -v -c

Important:
  - All parameters marked as (Required) must be provided.
  - If any required parameter is missing, the script will terminate with an error.
"
}

#prints message only if verbose mode is enabled
function log_verbose() {
    if [[ "$verbose" == "true" ]]; then
        echo -e "$1"
    fi
}

#check if variable is set. Ff not it give an error
function check_if_var_containerName_is_set() {
    if [[ -z "$containerName" ]]; then
        echo -e "${RED}The container name is not set. If you need help type the "--help" parameter...${RESET}"
        return 1
    fi
}

#checks if a variable is set; prints an error if it is not
function check_if_var_backupDirectory_is_set() {
    if [[ -z "$backupDirectory" ]]; then
        echo -e "${RED}The destination for the backup is not set. If you need help type the "--help" parameter...${RESET}"
        return 1
    fi
}

#checks if a variable is set; prints an error if it is not
function check_if_var_postgres_user_is_set() {
    if [[ -z "$postgres_user" ]]; then
        echo -e "${RED}The postgres user is not set. If you need help type the "--help" parameter...${RESET}"
        return 1
    fi
}

#checks if a variable is set; prints an error if it is not
function check_if_var_postgres_password_is_set() {
    if [[ -z "$postgres_password" ]]; then
        echo -e "${RED}The postgres password is not set. If you need help type the "--help" parameter...${RESET}"
        return 1
    fi
}

#check if Docker is installed
function check_if_docker_version_28_is_installed() {
	log_verbose "${YELLOW}Checking if Docker is installed...${RESET}"

	#check for common docker binaries
	if [[ ! -f /usr/bin/docker ]]; then
		echo -e "${RED}Docker does not appear to be installed on this system.${RESET}"
		return 1
	fi

	#check if its version 28.x
	local dockerVersion=$(docker version --format '{{.Client.Version}}' | grep -oP '^\K[0-9]+' | head -1)

	if [[ "$dockerVersion" == "28" ]]; then
		log_verbose "${GREEN}Docker Version 28.x detectet.${RESET}"
		return 0
	else
		echo -e "${RED}Docker Version 28.x is required. Found version: $dockerVersion${RESET}"
		return 1

	fi
}
#check if the docker daemon is running
function check_if_docker_daemon_is_running() {
	
	log_verbose "${YELLOW}Checking if Docker Deamon is running...${RESET}"

	#check for active docker process
	local dockerStatus=$(systemctl is-active docker | head -1)
	if [[ $dockerStatus == "inactive" ]]; then
		echo -e "${RED}Docker Daemon does not apear to be running on this system. Starting the Service ...${RESET}"
		sudo systemctl start docker
		sudo systemctl start docker.socket
        return 1
	else
		log_verbose "${GREEN}Docker Daemon is running.${RESET}"
        return 0
	fi
}

#waiting and check for the docker service to start
function wait_for_docker_service() {
    log_verbose "${RED}Checking if docker service got started...${RESET}"
    sleep 5
    dockerStatus=$(systemctl is-active docker | head -1)

    if [[ $dockerStatus == "active" ]]; then
        echo -e "${GREEN}The docker service got started successfully.${RESET}"
    else
        echo -e "${RED}The service could not start successfully. Exiting...${RESET}"
        return 1
    fi
}

#check if the database container is running
function check_if_db_container_is_running() {
	log_verbose "${YELLOW}Checking if Postgres DB is running...${RESET}"
	
	
	local postgresStatus=$(docker ps --filter "name=$containerName" | tail -n +2) 
	if [[ -z "$postgresStatus" ]]; then
		echo -e "${RED}The Container: $containerName does not apear be running. Exiting the process...${RESET}"
		exit 1
	else
		log_verbose "${GREEN}Container is running...${RESET}"
	fi
}

#generate checksum for the backup; the checksum will be saved in the _full folder
function backupGenerateChecksum() {
    log_verbose "${YELLOW}Generating Checksum for Backup $backup_output_folder_name...${RESET}"
    
    #calculate the checksum for all files in the backup directory
    sha256sum $(find "${backupDirectory%/}/${backup_output_folder_name%/}_full/${backup_output_folder_name%/}" -type f) | sha256sum > "${backupDirectory%/}/${backup_output_folder_name%/}_full/checksum.sha256"

    if [ "$?" -ne 0 ]; then
        return 1
    else
        return 0
    fi

}

#check if the directory exists
function clear_backup_tmp_folder() {

    #if the directory exists the directory will be deletet
    local directory_exists=$(docker exec $containerName test -d "${container_tmp_backup_folder%/}/${backup_output_folder_name}" && echo "exists" || echo "not exists")
    if [[ "$directory_exists" == "exists" ]]; then
        log_verbose "${YELLOW}Deleting temporary backup directory...${RESET}"
        docker exec $containerName rm -r "${container_tmp_backup_folder%/}/${backup_output_folder_name}"
    fi

}

#creating backup.lock file
function create_backup_lock_file() {

    #creating bckup.lock file in db /tmp directory
    local delete_backup_lock_file=$(docker exec $containerName test -f "$container_backup_lock_file_path" && echo "exists" || echo "not exists")
    if [[ "$delete_backup_lock_file" == "not exists" ]]; then
        log_verbose "${YELLOW}Creating backup lock file...${RESET}"
        docker exec $containerName touch "$container_backup_lock_file_path"
    fi
    
}

#check if backup.lock file exists or not
function check_backup_lock_file() {
    #checks if an backups is already running
    local check_if_backup_lock_file_exists=$(docker exec $containerName test -f "$container_backup_lock_file_path" && echo "exists" || echo "not exists")
    if [[ "$check_if_backup_lock_file_exists" == "exists" ]]; then
        return 1
    fi

}

#delete backup.lock file
function delete_backup_lock_file() {
    
    #deleting the backup.lock fie in the db /tmp folder
    local delete_backup_lock_file=$(docker exec $containerName test -f "$container_backup_lock_file_path" && echo "exists" || echo "not exists")
    if [[ "$delete_backup_lock_file" == "exists" ]]; then
        log_verbose "${YELLOW}Deleting backup lock file...${RESET}"
        docker exec $containerName rm "$container_backup_lock_file_path"
    fi

}

#backup the current postgres db data and safe it in de /tmp folder
function backup_postgres_db_container() {
    log_verbose "${YELLOW}Starting PostgreSQL backup on container '$containerName'...${RESET}"
    
    #set folder name with timestamp
    backup_output_folder_name="pg_${containerName}_${timestamp}"

    # Check if backup directory exists, create if necessary
    local backup_dir_created=$(docker exec -e PGPASSWORD=$postgres_password "$containerName" \
    bash -c "mkdir -p "${container_tmp_backup_folder%/}/${backup_output_folder_name}" && echo 'Backup directory created'")
    
    if [[ -z "$backup_dir_created" ]]; then
        echo -e "${RED}Failed to create backup directory inside the container.${RESET}"
        return 1
    fi
    
    #run pg_basebackup inside the container
    local backup_status=$(docker exec -e PGPASSWORD=$postgres_password "$containerName" \
    bash -c "pg_basebackup -U $postgres_user -D "${container_tmp_backup_folder%/}/${backup_output_folder_name}" -Fp -Xs -P -v -R")
    
    #check if the pg_basebackup command succeeded
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}PostgreSQL backup failed.${RESET}"
        echo -e "${RED}Error Details: $backup_status${RESET}"
        return 1
    fi
    
}

#copy the backup from db /tmp to the original wanted destination directory
function copy_backup_files_from_container_to_output_folder() {
    
    log_verbose "${YELLOW}Copying backuped files in the host output directory...${RESET}"

    docker cp $containerName:"${container_tmp_backup_folder%/}/${backup_output_folder_name}" $backupDirectory

}

#delete the current backups files in db /tmp
function delete_backup_files_from_postgres_container() {

    log_verbose "${YELLOW}Deleting the themory backup in container${RESET}"

    docker exec "$containerName" bash -c "rm -r ${container_tmp_backup_folder%/}/${backup_output_folder_name}"
    
}

#create warpping folder to place in the backup folder and the checksum file
function create_wrap_backup_directory_for_checksum() {

    log_verbose "${YELLOW}Creating wraping folder...${RESET}"

    mkdir -p "${backupDirectory%/}/${backup_output_folder_name}_full" 
}

#copy the backup folder in the wraping folder
function copy_backup_folder_in_wrap_folder() {
    log_verbose "${YELLOW}Moving the bacup folder in the wrapping folder...${RESET}"

    mv "${backupDirectory%/}/${backup_output_folder_name}" "${backupDirectory%/}/${backup_output_folder_name}_full"  
}

#needed vars
backup_output_folder_name="" # trennen von pfad und ordner namen


####
#### ---MAIN SCRIPT---
####

parse_parameters "$@"

if ! check_if_docker_version_28_is_installed; then
    echo -e "${RED}Docker Version 28.x is required. Exiting...${RESET}"
    exit 1
fi

if ! check_if_docker_daemon_is_running; then
    if ! wait_for_docker_service; then
        exit 1
    fi
fi

if ! check_if_var_containerName_is_set; then
    exit 1
fi

if ! check_if_db_container_is_running; then
    exit 1
fi

if ! check_if_var_backupDirectory_is_set; then
    exit 1
fi

if ! check_if_var_postgres_user_is_set; then
    exit 1
fi

if ! check_if_var_postgres_password_is_set; then
    exit 1
fi

if ! check_backup_lock_file; then
    echo -e "${RED}An Backup is already running. Backup will be canceled...${RESET}"
    exit 1
fi

create_backup_lock_file
backup_postgres_db_container

if [ $? -eq 0 ]; then
    echo -e "${GREEN}PostgreSQL backup completed successfully.${RESET}"
    delete_backup_lock_file
fi

if [ $? -ne 0 ]; then
    delete_backup_lock_file
    exit 1
fi

copy_backup_files_from_container_to_output_folder

if [ $? -ne 0 ]; then
    delete_backup_lock_file
    exit 1
fi

delete_backup_files_from_postgres_container
delete_backup_lock_file

#if checksum is true
if [[ "$checksum" == "true" ]]; then
    create_wrap_backup_directory_for_checksum
    copy_backup_folder_in_wrap_folder
    backupGenerateChecksum

fi