

function die()
{
    echo "::error::$1"
    echo "------------------------------------------------------------------------------------------------------------------------"
    exit 1
}

function finish()
{
    echo "$1"
    echo "------------------------------------------------------------------------------------------------------------------------"
    exit 0
}

function infomsg()
{
	echo -e "\n${1}\n"
}

# Replace all matches for given sed regex with given replace_value.
#
# Exit codes:
#   0 - success
#   3 - no match for regex
#   5 - file not found
#
# $1: regex
# $2: replace_value
# $3: target_file
# $4: sed_delimiter - optional, default: %
function replace_in_file()
{
    regex="$1"
    replace_value="$2"
    target_file="$3"
    sed_delimiter="${4:-%}"
    [ ! -f "${target_file}" ] && return 5
    # shellcheck disable=SC2016
    /bin/sed -i "\\${sed_delimiter}${regex}${sed_delimiter},\${s${sed_delimiter}${sed_delimiter}${replace_value}${sed_delimiter}g"';b};$q3' \
        "${target_file}"
}

# Find the ebuild template and strip the .gentoo/ prefix 
# e.g. dev-libs/hacking-bash-lib/hacking-bash-lib-9999.ebuild
function find_ebuild_template()
{
	local ebuild_path
	ebuild_path=$(find .gentoo -iname '*-9999.ebuild' | head -1)
	ebuild_path="${ebuild_path#*/}"
	[[ -z "${ebuild_path}" ]] && die "Unable to find a template ebuild in .gentoo subdirectory of ${PWD}"
	echo "${ebuild_path}"
}

# Calculate the ebuild package category
#
# $1 - ebuild path
# stdout - ebuild category - e.g. dev-libs
#
function get_ebuild_cat()
{
	local ebuild_cat
	ebuild_cat="${1%%/*}"
	[[ -z "${ebuild_cat}" ]] && die "Unable to calculate ebuild category"
	echo "${ebuild_cat}"
}

# Calculate the ebuild package name
#
# $1 - ebuild path
# stdout - ebuild package - e.g. hacking-bash-lib
#
function get_ebuild_pkg()
{
	local ebuild_pkg
	ebuild_pkg="${1%-*}"
	ebuild_pkg="${ebuild_pkg##*/}"
	[[ -z "${ebuild_pkg}" ]] && die "Unable to calculate ebuild package"
	echo "${ebuild_pkg}"
}

# Calculate the ebuild file name
#
# $1 - ebuild path
# stdout - ebuild name - e.g. hacking-bash-lib-9999.ebuild 
#
function get_ebuild_name()
{
	local ebuild_name
	ebuild_name="${1##*/}"
	[[ -z "${ebuild_name}" ]] && die "Unable to calculate ebuild name"
	echo "${ebuild_name}"
}

# Work out from the tag what version we are releasing
#
# $1 - GITHUB_REF
# stdout - version number - e.g. 1.0.0
#
function get_ebuild_ver()
{
	local semver_regex ebuild_ver
	semver_regex="^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))*$"
	ebuild_ver="${1##*/}"
	[[ ${ebuild_ver} =~ ${semver_regex} ]] || die "Unexpected release version - ${ebuild_ver}"
	echo "${ebuild_ver}"
}

# Configure the ssh-agent by adding github.com to known_hosts and 
# the deploy key to the authentication agent.
#
# $1 - deploy key 
#
function configure_ssh()
{
	infomsg "Configuring ssh agent"
	eval "$(ssh-agent -s)"
	mkdir -p /root/.ssh
	ssh-keyscan github.com >> /root/.ssh/known_hosts
	echo "${1}" | ssh-add -
	ssh-add -l
}

# Configure git by setting a global user.name and user.email
#
# $1 - actor name
#
function configure_git()
{
	infomsg "Configuring git"
	git config --global user.name "${1}"
	git config --global user.email "${1}@github.com"
}

# Check out the specified overlay repository
#
# $1 - address of the git repository
#
function checkout_overlay_master()
{
	infomsg "Checking out overlay (master)"
	local overlay_dir="/var/db/repos/action-ebuild-release"
	mkdir -p "${overlay_dir}"
	cd "${overlay_dir}" || die "Unable to change to overlay directory (${overlay_dir})"
	git init
	git remote add github "git@github.com:${1}.git"
	git pull github master
} 

# Check out or create the specified branch
#
# $1 - the name of the branch
#
function checkout_or_create_overlay_branch()
{
	infomsg "Checking out or creating overlay branch (${1})"
	git pull github "${1}" 2>/dev/null || true
	git checkout -b "${1}"
}

# Attempt to rebase the current branch against master ignoring errors
#
function rebase_overlay_branch()
{
	infomsg "Attempting to rebase against master"
	git rebase master || true
}

# Add all files in the current working directory to git
#
function git_add_files()
{
	infomsg "Adding files to git"
	git add .
}

# Commit the changes to the git repository in CWD
#
# $1 - commit message
#
function git_commit()
{
	infomsg "Committing new ebuild"
	git commit -m "${1}"
}

# Push the git repository in the CWD 
#
# $1 - branch name
#
function git_push()
{
	infomsg "Pushing to git repository"
	git push --force --set-upstream github "${1}"
}

# Configure the overlay in repos.conf
#
function configure_overlay()
{
	local repo_name
	
	infomsg "Adding overlay to repos.conf"
	repo_name="$(cat profiles/repo_name 2>/dev/null || true)"
	[[ -z "${repo_name}" ]] && repo_name="action-ebuild-release"
	cat << END > /etc/portage/repos.conf/action-ebuild-release
[${repo_name}]
priority = 50
location = /var/db/repos/action-ebuild-release
END
	echo "${repo_name}"
}

# Check that an ebuild category exists and create it if not.
#
# $1 - ebuild category - eg "dev-libs"
#
function check_ebuild_category()
{
	infomsg "Checking this ebuild's category (${1}) is present in categories file"
	mkdir -p profiles
	echo "${1}" >> profiles/categories
	sort -u -o profiles/categories profiles/categories
}

# Copy an ebuild directory
#
# $1 - ebuild category - eg "dev-libs"
# $2 - ebuild package  - eg "hacking-bash-lib"
#
function copy_ebuild_directory()
{
	infomsg "Copying ebuild directory"
	mkdir -p "${1}/${2}" || die "Unable to create ${PWD}/${1}/${2}"
	cp -R "${GITHUB_WORKSPACE}/.gentoo/${1}/${2}"/* "${1}/${2}/" || die "Unable to copy ebuild directory"
}

# Create a test ebuild in the test overlay from a template
#
# $1 - repository path
# $2 - repository id
# $3 - ebuild category
# $4 - ebuild package
# $5 - ebuild template filename
# $6 - ebuild path
#
function create_test_ebuild()
{
	local repo_path repo_id ebuild_cat ebuild_pkg ebuild_name ebuild_path
	repo_path="${1}"
	repo_id="${2}"
	ebuild_cat="${3}"
	ebuild_pkg="${4}"
	ebuild_name="${5}"
	ebuild_path="${6}"
	
	infomsg "Configuring package in test overlay"
	mkdir -p "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}" "${repo_path}/${repo_id}/metadata" "${repo_path}/${repo_id}/profiles"
	echo "masters = gentoo" >> "${repo_path}/${repo_id}/metadata/layout.conf"
	echo "${ebuild_cat}" >> "${repo_path}/${repo_id}/profiles/categories"
	echo "${repo_id}" >> "${repo_path}/${repo_id}/profiles/repo_name"
	cp -r ".gentoo/${ebuild_cat}/${ebuild_pkg}"/* "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/"
	unexpand --first-only -t 4 ".gentoo/${ebuild_path}" > "${repo_path}/${repo_id}/${ebuild_path}"
	if [[ "${INPUT_PACKAGE_ONLY}" != "true" ]]; then
		sed-or-die "GITHUB_REPOSITORY" "${GITHUB_REPOSITORY}" "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/${ebuild_name}"
		sed-or-die "GITHUB_REF" "${git_branch:-master}" "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/${ebuild_name}"
	fi
	ebuild "${repo_path}/${repo_id}/${ebuild_cat}/${ebuild_pkg}/${ebuild_name}" manifest
}

# Create live ebuild from template
#
# $1 - ebuild category - eg "dev-libs"
# $2 - ebuild package  - eg "hacking-bash-lib"
# $3 - ebuild name     - eg "hacking-bash-lib-9999.ebuild"
#
function create_live_ebuild()
{
	local ebuild_file_live	
	ebuild_file_live="${1}/${2}/${3}"
	infomsg "Creating live ebuild (${ebuild_file_live})"
	unexpand --first-only -t 4 "${GITHUB_WORKSPACE}/.gentoo/${ebuild_file_live}" > "${ebuild_file_live}" 
	if [[ "${INPUT_PACKAGE_ONLY}" != "true" ]]; then
		replace_in_file "GITHUB_REPOSITORY" "${GITHUB_REPOSITORY}" "${ebuild_file_live}"
		replace_in_file "GITHUB_REF" "master" "${ebuild_file_live}"
	fi
	
	# Fix up the KEYWORDS variable in the new ebuild - 9999 live version.
	infomsg "Fixing up KEYWORDS variable in new ebuild - live version"
	sed -i 's/^KEYWORDS.*/KEYWORDS=""/g' "${ebuild_file_live}"
	
	# Build / rebuild manifests
	infomsg "Rebuilding manifests (live ebuild)" 
	ebuild "${ebuild_file_live}" manifest --force
}

# Create a new versioned ebuild from the template
#
# $1 - ebuild category - eg "dev-libs"
# $2 - ebuild package  - eg "hacking-bash-lib"
# $3 - ebuild version  - eg "2.1.3"
# $4 - ebuild path     - eg "dev-libs/hacking-bash-lib/hacking-bash-lib-9999.ebuild"
# $5 - repository name - eg "hacking-gentoo"
#
function create_new_ebuild()
{
	local ebuild_cat ebuild_pkg ebuild_ver ebuild_path repo_name
	ebuild_cat="${1}"
	ebuild_pkg="${2}"
	ebuild_ver="${3}"
	ebuild_path="${4}"
	repo_name="${5}"
	
	ebuild_file_new="${ebuild_cat}/${ebuild_pkg}/${ebuild_pkg}-${ebuild_ver}.ebuild"
	infomsg "Creating new ebuild (${ebuild_file_new})"
	rm -rf "${ebuild_file_new}"
	unexpand --first-only -t 4 "${GITHUB_WORKSPACE}/.gentoo/${ebuild_path}" > "${ebuild_file_new}"
	if [[ "${INPUT_PACKAGE_ONLY}" != "true" ]]; then
		replace_in_file "GITHUB_REPOSITORY" "${GITHUB_REPOSITORY}" "${ebuild_file_new}"
		replace_in_file "GITHUB_REF" "master" "${ebuild_file_new}"
	fi
	
	# Build / rebuild manifests
	infomsg "Rebuilding manifests (new ebuild)" 
	ebuild "${ebuild_file_new}" manifest --force
	
	infomsg "New ebuild (${ebuild_file_new}):" 
	cat "${ebuild_file_new}"
	
	# If no KEYWORDS are specified try to calculate the best keywords
	if [[ -z "$(unstable_keywords "${ebuild_file_new}")" ]]; then
		echo "kwtool b ${ebuild_cat}/${ebuild_pkg}-${ebuild_ver}::${repo_name}"
		kwtool -N b "${ebuild_cat}/${ebuild_pkg}-${ebuild_ver}::${repo_name}"
		new_keywords="$(kwtool b "${ebuild_cat}/${ebuild_pkg}-${ebuild_ver}")"
		echo "Using best keywords: ${new_keywords}"
		sed-or-die '^KEYWORDS.*' "KEYWORDS=\"${new_keywords}\"" "${ebuild_file_new}"
	fi
	
	# If this is a pre-release then fix the KEYWORDS variable
	if [[ $(jq ".release.prerelease" "${GITHUB_EVENT_PATH}") == "true" ]]; then
		new_keywords="$(unstable_keywords "${ebuild_file_new}")"
		sed-or-die '^KEYWORDS.*' "KEYWORDS=\"${new_keywords}\"" "${ebuild_file_new}"
	fi
	
	# Build / rebuild manifests
	infomsg "Rebuilding manifests (new ebuild, pass two)" 
	ebuild "${ebuild_file_new}" manifest --force
}

# Install dependencies of test ebuild
#
# $1 - ebuild category
# $2 - ebuild package
# $3 - repository id
#
function install_ebuild_deps()
{
	infomsg "Installing dependencies of test ebuild"
	emerge --autounmask y --autounmask-write y --autounmask-only y "${1}/${2}::${3}" || \
	    die "Unable to un-mask dependencies"
	etc-update --automode -5
	emerge --onlydeps "${1}/${2}::${3}" || die "Unable to merge dependencies"
}

# Run ebuild tests
#
# $1 - path to the ebuild to test
#
function run_ebuild_tests()
{
	infomsg "Testing the ebuild"
	TERM="dumb" ebuild "${1}" test || die "Package failed tests"
}

# Run coverage test script and upload coverage report using codecov
#
# $1 - ebuild category
# $2 - ebuild package
#
function run_coverage_tests()
{
	local ebuild_cat ebuild_pkg
	ebuild_cat="${1}"
	ebuild_pkg="${2}"
	
	infomsg "Performing coverage tests"
    chmod g+rX -R /var/tmp/portage
    pushd "/var/tmp/portage/${ebuild_cat}/${ebuild_pkg}-9999/work/${ebuild_pkg}-9999/" >/dev/null || die "Unable to change to build directory" 
    su --preserve-environment testrunner -c "${GITHUB_WORKSPACE}/.gentoo/coverage.sh" || die "Test coverage report generation failed"
    popd || die "Unexpected popd error!"
    codecov -s /var/tmp/coverage -B "${GITHUB_REF##*/}" || die "Unable to upload coverage report"
}

# Run the merge phase of an ebuild
#
# $1 - path to the ebuild to merge
#
function merge_ebuild()
{
	infomsg "Merging the test ebuild"
	ebuild "${1}" merge || die "Package failed merge"
}

# Check the overlay in the CWD with repoman
#
function repoman_check()
{
	infomsg "Checking with repoman"
	repoman --straight-to-stable -dx full
}

# Create a pull request
#
# $1 - source branch
# $2 - destination branch
# $3 - title
# $4 - message
# $5 - draft (true/false)
#
function create_pull_request() 
{
	infomsg "Creating pull request" 

	local src tgt title body draft api_ver base_url auth_hdr header pulls_url repo_base query_url resp pr data
	
    src="${1}"		# from this branch
    tgt="${2}"		# pull request TO this target
    title="${3}"	# pull request title
    body="${4}"		# this is the content of the message

	[[ -z "${src}" ]] && die "create_pull_request() requires a source branch as parameter 1"
	[[ -z "${tgt}" ]] && die "create_pull_request() requires a target branch as parameter 2"
	[[ -z "${title}" ]] && die "create_pull_request() requires a title as parameter 3"
	[[ -z "${body}" ]] && die "create_pull_request() requires a body as parameter 4"

    if [[ "${5}" ==  "true" ]]; then
      draft="true";
    else
      draft="false";
    fi

	api_ver="v3"
	base_url="https://api.github.com"
	auth_hdr="Authorization: token ${INPUT_AUTH_TOKEN}"
	header="Accept: application/vnd.github.${api_ver}+json; application/vnd.github.antiope-preview+json; application/vnd.github.shadow-cat-preview+json"
	pulls_url="${base_url}/repos/${INPUT_OVERLAY_REPO}/pulls"
	repo_base="${INPUT_OVERLAY_REPO%/*}"

    # Check if the branch already has a pull request open
    query_url="${pulls_url}?base=${tgt}&head=${repo_base}:${src}&state=open"
    echo "curl -sSL -H \"${auth_hdr}\" -H \"${header}\" --user \"${GITHUB_ACTOR}:\" -X GET \"${query_url}\""
    resp=$(curl -sSL -H "${auth_hdr}" -H "${header}" --user "${GITHUB_ACTOR}:" -X GET "${query_url}")
    echo -e "Raw response:\n${resp}"
    pr=$(echo "${resp}" | jq --raw-output '.[] | .head.ref')
    echo "Response ref: ${pr}"

    if [[ -n "${pr}" ]]; then
	    # A pull request is already open
        echo "Pull request from ${src} to ${tgt} is already open!"
    else
        # Post new pull request
        data="{ \"base\":\"${tgt}\", \"head\":\"${src}\", \"title\":\"${title}\", \"body\":\"${body}\", \"draft\":${draft} }"
        echo "curl -sSL -H \"${auth_hdr}\" -H \"${header}\" --user \"${GITHUB_ACTOR}:\" -X POST --data \"${data}\" \"${pulls_url}\""
        curl -sSL -H "${auth_hdr}" -H "${header}" --user "${GITHUB_ACTOR}:" -X POST --data "${data}" "${pulls_url}" || \
        	die "Unable to create pull request"
    fi
}

# Clean redundant binary packages
function clean_binary_packages()
{
	infomsg "Cleaning any redundant binary packages"
	eclean-pkg --deep
}

# Clean redundant distfiles
function clean_distfiles()
{
	infomsg "Cleaning any redundant distfiles"
	eclean-dist --deep
}
