DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1

failed=0

for filter in files/*; do
	name=$(basename "$filter")
	testlog="test_logs/$name"

	if [[ ! -f "$testlog" ]]; then
		echo "WARNING: No test log for filter: $name"
		continue
	fi

	remaining=$(grep -E -v --file "$filter" "$testlog")
	if [[ -n "$remaining" ]]; then
		echo "FAIL: $name - unmatched lines:"
		echo "$remaining"
		failed=1
	fi
done

for testlog in test_logs/*; do
	name=$(basename "$testlog")
	if [[ ! -f "files/$name" ]]; then
		echo "WARNING: No filter for test log: $name"
		failed=1
	fi
done

if [[ $failed -eq 1 ]]; then
	echo "Test failed: Some log entries were not matched."
	exit 1
else
	echo "PASS: All logcheck log entries successfully matched."
fi
