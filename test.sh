#!/bin/bash
set -eux


check_deps()
{
        if !hash cppcheck 2>/dev/null; then
               echo "Please install cppchecki"
        fi
}

build_babel()
{
        cores=$(grep -c ^processor /proc/cpuinfo)
        make clean
        make -j $cores
	if [ $? -ne 0 ]
	then
		echo "Compile failed!"
		exit 1
        fi
}

run_lint()
{
        cppcheck --force .
	if [ $? -ne 0 ]
	then
		echo "Linting failed!"
		exit 1
        fi
        echo "Linting successful"
}

run_integration_tests()
{
        pushd tests
                sudo bash ./multihop-basic.sh
		if [ $? -ne 0 ]
		then
			echo "Integration test failed!"
			exit 1
		fi
        popd
}

if [ -z "$CI" ]; then
	check_deps
	build_babel
	run_lint
	run_integration_tests
else
	if [ "$TEST" == "lint" ]; then
		run_lint
	elif [ "$TEST" == "build" ]; then
		build_babel
	elif [ "$TEST" == "integration" ]; then
		build_babel
		run_integration_tests
	fi
fi
