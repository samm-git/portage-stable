# Copyright 1999-2019 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: cargo.eclass
# @MAINTAINER:
# rust@gentoo.org
# @AUTHOR:
# Doug Goldstein <cardoe@gentoo.org>
# @SUPPORTED_EAPIS: 6 7
# @BLURB: common functions and variables for cargo builds

if [[ -z ${_CARGO_ECLASS} ]]; then
_CARGO_ECLASS=1

CARGO_DEPEND=""
[[ ${CATEGORY}/${PN} != dev-util/cargo ]] && CARGO_DEPEND="virtual/cargo"

case ${EAPI} in
	6) DEPEND="${CARGO_DEPEND}";;
	7) BDEPEND="${CARGO_DEPEND}";;
	*) die "EAPI=${EAPI:-0} is not supported" ;;
esac

inherit multiprocessing

EXPORT_FUNCTIONS src_unpack src_compile src_install src_test

IUSE="${IUSE} debug"

ECARGO_HOME="${WORKDIR}/cargo_home"
ECARGO_VENDOR="${ECARGO_HOME}/gentoo"

# @FUNCTION: cargo_crate_uris
# @DESCRIPTION:
# Generates the URIs to put in SRC_URI to help fetch dependencies.
cargo_crate_uris() {
	local crate
	for crate in "$@"; do
		local name version url pretag
		name="${crate%-*}"
		version="${crate##*-}"
		pretag="^[a-zA-Z]+"
		if [[ $version =~ $pretag ]]; then
			version="${name##*-}-${version}"
			name="${name%-*}"
		fi
		url="https://crates.io/api/v1/crates/${name}/${version}/download -> ${crate}.crate"
		echo "${url}"
	done
}

# @FUNCTION: cargo_src_unpack
# @DESCRIPTION:
# Unpacks the package and the cargo registry
cargo_src_unpack() {
	debug-print-function ${FUNCNAME} "$@"

	mkdir -p "${ECARGO_VENDOR}" || die
	mkdir -p "${S}" || die

	local archive shasum pkg
	for archive in ${A}; do
		case "${archive}" in
			*.crate)
				ebegin "Loading ${archive} into Cargo registry"
				tar -xf "${DISTDIR}"/${archive} -C "${ECARGO_VENDOR}/" || die
				# generate sha256sum of the crate itself as cargo needs this
				shasum=$(sha256sum "${DISTDIR}"/${archive} | cut -d ' ' -f 1)
				pkg=$(basename ${archive} .crate)
				cat <<- EOF > ${ECARGO_VENDOR}/${pkg}/.cargo-checksum.json
				{
					"package": "${shasum}",
					"files": {}
				}
				EOF
				# if this is our target package we need it in ${WORKDIR} too
				# to make ${S} (and handle any revisions too)
				if [[ ${P} == ${pkg}* ]]; then
					tar -xf "${DISTDIR}"/${archive} -C "${WORKDIR}" || die
				fi
				eend $?
				;;
			cargo-snapshot*)
				ebegin "Unpacking ${archive}"
				mkdir -p "${S}"/target/snapshot
				tar -xzf "${DISTDIR}"/${archive} -C "${S}"/target/snapshot --strip-components 2 || die
				# cargo's makefile needs this otherwise it will try to
				# download it
				touch "${S}"/target/snapshot/bin/cargo || die
				eend $?
				;;
			*)
				unpack ${archive}
				;;
		esac
	done

	cargo_gen_config
}

# @FUNCTION: cargo_gen_config
# @DESCRIPTION:
# Generate the $CARGO_HOME/config necessary to use our local registry
cargo_gen_config() {
	debug-print-function ${FUNCNAME} "$@"

	cat <<- EOF > "${ECARGO_HOME}/config"
	[source.gentoo]
	directory = "${ECARGO_VENDOR}"

	[source.crates-io]
	replace-with = "gentoo"
	local-registry = "/nonexistant"
	EOF
}

# @FUNCTION: cargo_src_compile
# @DESCRIPTION:
# Build the package using cargo build
cargo_src_compile() {
	debug-print-function ${FUNCNAME} "$@"

	export CARGO_HOME="${ECARGO_HOME}"

	cargo build -j $(makeopts_jobs) $(usex debug "" --release) "$@" \
		|| die "cargo build failed"
}

# @FUNCTION: cargo_src_install
# @DESCRIPTION:
# Installs the binaries generated by cargo
cargo_src_install() {
	debug-print-function ${FUNCNAME} "$@"

	cargo install -j $(makeopts_jobs) --root="${D}/usr" $(usex debug --debug "") "$@" \
		|| die "cargo install failed"
	rm -f "${ED}/usr/.crates.toml"
	rm -f "${ED}/usr/.crates2.json"

	[ -d "${S}/man" ] && doman "${S}/man" || return 0
}

# @FUNCTION: cargo_src_test
# @DESCRIPTION:
# Test the package using cargo test
cargo_src_test() {
	debug-print-function ${FUNCNAME} "$@"

	cargo test -j $(makeopts_jobs) $(usex debug "" --release) "$@" \
		|| die "cargo test failed"
}

fi
