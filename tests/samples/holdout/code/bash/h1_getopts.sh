while getopts "f:v" opt; do
  case $opt in
    f) FILE="$OPTARG" ;;
    v) VERBOSE=1 ;;
  esac
done