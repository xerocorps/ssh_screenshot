#!/bin/bash

# Function to show usage instructions
usage() {
    cat <<EOF
Usage: $0 [options]
Options:
  -u, --url <URL>             Take screenshot of single URL
  -f, --file <file>           Take screenshots of URLs from file
  -w, --width <width>         Set custom width (default: 1024)
  -h, --height <height>       Set custom height (default: 768)
  -p, --port <port>           Set custom port for xvfb-run (default: 99)
  -o, --output <dir>          Set output directory for screenshots (default: current directory)
  -r, --retry <num>           Number of retries for 429 errors (default: 0)
  -d, --delay <seconds>       Delay between retries in seconds (default: 1)
  -l, --limit <num>           Requests per second limit (default: 1)
      --follow-redirects      Follow HTTP redirects (default: false)
      --no-javascript         Disable JavaScript execution (default: false)
  -s, --delay-screenshot <seconds>   Delay before taking screenshot in seconds (default: 0)
  -t, --timeout <seconds>     Timeout for webpage in seconds (default: 0, no timeout)
  -H, --headers <headers>     Set custom headers for browsing (format: "Header1: Value1, Header2: Value2")
  -h, --help                  Show this help message
EOF
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -u|--url)
            URL="$2"
            shift
            shift
            ;;
        -f|--file)
            FILE="$2"
            shift
            shift
            ;;
        -w|--width)
            WIDTH="$2"
            shift
            shift
            ;;
        -h|--height)
            HEIGHT="$2"
            shift
            shift
            ;;
        -p|--port)
            PORT="$2"
            shift
            shift
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift
            shift
            ;;
        -r|--retry)
            RETRY="$2"
            shift
            shift
            ;;
        -d|--delay)
            DELAY="$2"
            shift
            shift
            ;;
        -l|--limit)
            LIMIT="$2"
            shift
            shift
            ;;
        --follow-redirects)
            FOLLOW_REDIRECTS=true
            shift
            ;;
        --no-javascript)
            DISABLE_JAVASCRIPT=true
            shift
            ;;
        -s|--delay-screenshot)
            DELAY_SCREENSHOT="$2"
            shift
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift
            shift
            ;;
        -H|--headers)
            HEADERS="$2"
            shift
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

# Set default values if not provided
WIDTH=${WIDTH:-1024}
HEIGHT=${HEIGHT:-768}
PORT=${PORT:-99}
OUTPUT_DIR=${OUTPUT_DIR:-$(pwd)}
RETRY=${RETRY:-0}
DELAY=${DELAY:-1}
LIMIT=${LIMIT:-1}
FOLLOW_REDIRECTS=${FOLLOW_REDIRECTS:-false}
DISABLE_JAVASCRIPT=${DISABLE_JAVASCRIPT:-false}
DELAY_SCREENSHOT=${DELAY_SCREENSHOT:-0}
TIMEOUT=${TIMEOUT:-0}
HEADERS=${HEADERS:-""}

# Function to format custom headers for browser
formatHeaders() {
    local headers="$1"
    local formattedHeaders=""

    IFS=',' read -r -a headerArray <<< "$headers"
    for header in "${headerArray[@]}"; do
        formattedHeaders+="--extra-http-header '$header' "
    done

    echo "$formattedHeaders"
}

# Function to take screenshot of a single URL with retry logic
takeSingleScreenshot() {
    local url="$1"
    local attempt=1
    local response_code

    # Format custom headers for browser
    IFS=',' read -ra headerArray <<< "$HEADERS"
    local formattedHeaders=""
    for header in "${headerArray[@]}"; do
        formattedHeaders+="\"${header}\""
        formattedHeaders+=","
    done
    formattedHeaders=$(echo "${formattedHeaders::-1}")  # Remove trailing comma

    while true; do
        # Capture screenshot
        xvfb-run --server-args="-screen 0 ${WIDTH}x${HEIGHT}x24" node - <<JS
const puppeteer = require('puppeteer');
const fs = require('fs');

(async () => {
    const browser = await puppeteer.launch({
        args: ['--no-sandbox'],
    });
    const page = await browser.newPage();
    await page.setViewport({ width: ${WIDTH}, height: ${HEIGHT} });
    await page.setRequestInterception(true);
    page.on('request', request => {
        if (request.resourceType() === 'document' && ${DISABLE_JAVASCRIPT}) {
            request.abort();
        } else {
            request.continue();
        }
    });
    try {
        await page.setExtraHTTPHeaders({
            ${formattedHeaders}
        });
        await Promise.race([
            page.goto('${url}', { waitUntil: 'domcontentloaded' }),
            new Promise((resolve, reject) => setTimeout(() => reject(new Error('Timeout')), ${TIMEOUT} * 1000))
        ]);
    } catch (error) {
        console.error('An error occurred while loading ${url}:', error);
        await browser.close();
        return;
    }
    await new Promise(resolve => setTimeout(resolve, ${DELAY_SCREENSHOT} * 1000));
    const screenshotName = '${OUTPUT_DIR}/screenshot_' + ${2} + '.png';
    await page.screenshot({ path: screenshotName });
    await browser.close();
    console.log('Screenshot saved as ' + screenshotName);
})();
JS
        # Check response code
        response_code=$?
        if [[ ${response_code} -eq 0 ]]; then
            break
        fi

        # Retry if necessary
        if [[ ${attempt} -le ${RETRY} ]]; then
            echo "Retrying (${attempt}/${RETRY})..."
            ((attempt++))
            sleep ${DELAY}
        else
            echo "Failed to capture screenshot for ${url} after ${RETRY} attempts."
            break
        fi
    done
}

# Function to take screenshots of multiple URLs from a file
takeMultipleScreenshotsFromFile() {
    local line_number=0
    while IFS= read -r line; do
        ((line_number++))
        takeSingleScreenshot "$line" "$line_number"
        sleep $(bc -l <<< "scale=2; 1 / $LIMIT")
    done < "$1"
}

# Main function
main() {
    # Check if either URL or FILE is provided
    if [ -n "$URL" ]; then
        takeSingleScreenshot "$URL" 1
    elif [ -n "$FILE" ]; then
        takeMultipleScreenshotsFromFile "$FILE"
    else
        # Read URLs from stdin
        echo "Enter URLs (one per line). Enter blank line to finish:"
        urls=()
        while IFS= read -r line; do
            [ -z "$line" ] && break
            urls+=("$line")
        done
        for ((i=0; i<${#urls[@]}; i++)); do
            takeSingleScreenshot "${urls[$i]}" "$((i+1))"
            sleep $(bc -l <<< "scale=2; 1 / $LIMIT")
        done
    fi
}

main
