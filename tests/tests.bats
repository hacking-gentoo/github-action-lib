#!/usr/bin/env bats

source usr/lib/github-action-lib.sh

load '/usr/lib/bats-support/load.bash'
load '/usr/lib/bats-assert/load.bash'
load '/usr/lib/bats-file/load.bash'

function setup() {
	:
}

function teardown() {
    :
}

@test "die" {
    run die "Message"
    
    assert_failure
    assert_line "::error::Message"
}

@test "infomsg" {
	run infomsg "A test message"
	
	assert_success
	assert_line "A test message"
}

@test "find_ebuild_template fail" {
	run find_ebuild_template
	
	assert_failure
}

@test "find_ebuild_template good" {
	
	function testit
	{
		cd ./tests/sup
		find_ebuild_template
	}
	run testit 
	
	assert_success
	assert_output "dev-libs/test-package/test-package-9999.ebuild"
}

@test "get_ebuild_cat" {
	run get_ebuild_cat "dev-libs/test-package/test-package-9999.ebuild"

	assert_success
	assert_output "dev-libs"
}

@test "get_ebuild_pkg" {
	run get_ebuild_pkg "dev-libs/test-package/test-package-9999.ebuild"

	assert_success
	assert_output "test-package"
}

@test "get_ebuild_name" {
	run get_ebuild_name "dev-libs/test-package/test-package-9999.ebuild"

	assert_success
	assert_output "test-package-9999.ebuild"
}

@test "get_ebuild_ver" {
	run get_ebuild_ver "refs/tags/1.23.4"
	
	assert_success
	assert_output "1.23.4"
}

@test "check_ebuild_category" {
	
    TEST_TEMP_DIR="$(temp_make)"

	function testit()
	{
		cd "$TEST_TEMP_DIR"
		check_ebuild_category "zap-frobulate" 
		check_ebuild_category "app-frobulate" 
		check_ebuild_category "app-frobulate" 
	}
	run testit

	assert_success
	assert_file_exist "$TEST_TEMP_DIR/profiles/categories"

	run cat "$TEST_TEMP_DIR/profiles/categories"
	
	assert_success
	assert_line --index 0 "app-frobulate"
	assert_line --index 1 "zap-frobulate"
	
	temp_del "$TEST_TEMP_DIR"
}

@test "copy_ebuild_directory" {
    TEST_TEMP_DIR="$(temp_make)"
	
	function testit()
	{
		GITHUB_WORKSPACE="$(realpath tests/sup)"
		cd "$TEST_TEMP_DIR"
		copy_ebuild_directory "dev-libs" "test-package"
	}
	run testit
	
	assert_success
	assert_file_exist "$TEST_TEMP_DIR/dev-libs/test-package/metadata.xml"
	assert_file_exist "$TEST_TEMP_DIR/dev-libs/test-package/test-package-9999.ebuild"
	assert_file_exist "$TEST_TEMP_DIR/dev-libs/test-package/files/somefile.txt"
	
	temp_del "$TEST_TEMP_DIR"
}

#@test "create_live_ebuild" {
#    TEST_TEMP_DIR="$(temp_make)"
#	
#	function testit()
#	{
#		GITHUB_WORKSPACE="$(realpath tests/sup)"
#		GITHUB_REPOSITORY="hacking-actions/test-package"
#		cd "$TEST_TEMP_DIR"
#		mkdir -p "dev-libs/test-package"
#		create_live_ebuild "dev-libs" "test-package" "test-package-9999.ebuild"
#	}
#	run testit
#	
#	assert_success
#	assert_file_exist "$TEST_TEMP_DIR/dev-libs/test-package/test-package-9999.ebuild"
#	assert_file_exist "$TEST_TEMP_DIR/dev-libs/test-package/Manifest"
#	
#	temp_del "$TEST_TEMP_DIR"
#}
#
#@test "create_new_ebuild" {
#    TEST_TEMP_DIR="$(temp_make)"
#	
#	function testit()
#	{
#		GITHUB_WORKSPACE="$(realpath tests/sup)"
#		GITHUB_EVENT_PATH="${GITHUB_WORKSPACE}/event.json"
#		GITHUB_REPOSITORY="hacking-actions/test-package"
#		cd "$TEST_TEMP_DIR"
#		mkdir -p "dev-libs/test-package"
#		create_new_ebuild "dev-libs" "test-package" "1.23.4" "dev-libs/test-package/test-package-9999.ebuild" "overfrob"
#	}
#	run testit
#	
#	assert_success
#	assert_file_exist "$TEST_TEMP_DIR/dev-libs/test-package/test-package-1.23.4.ebuild"
#	assert_file_exist "$TEST_TEMP_DIR/dev-libs/test-package/Manifest"
#	
#	temp_del "$TEST_TEMP_DIR"
#}







