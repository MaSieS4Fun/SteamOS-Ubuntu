project(
	'edid-decode',
	'cpp',
)

edid_decode_args = [
	'-Wno-missing-field-initializers',
	'-Wno-unused-parameter',
	'-Wimplicit-fallthrough',
	'-Wno-variadic-macros',
]
edid_decode_link_args = []

git = find_program('git', native: true, required: false)
if git.found()
	git_commit = run_command(
		[git, 'rev-parse', '--short=12', 'HEAD'],
		check: false,
	)
	git_date = run_command(
		[git, 'show', '--quiet', '--date=format-local:%F %T', '--format=%cd'],
		env: {'TZ': 'UTC'},
		check: false,
	)

	if git_commit.returncode() == 0
		edid_decode_args += ['-DSHA=' + git_commit.stdout().strip()]
	endif
	if git_date.returncode() == 0
		edid_decode_args += ['-DDATE=' + git_date.stdout().strip()]
	endif
endif

if target_machine.system() == 'emscripten'
	edid_decode_link_args += [
		'-sEXPORTED_FUNCTIONS=_parse_edid',
		'-sEXPORTED_RUNTIME_METHODS=ccall,cwrap'
	]

	fs = import('fs')
	foreach filename : ['edid-decode.html', 'edid-decode.ico']
		fs.copyfile(
			'emscripten' / filename,
			install: true,
			install_dir: 'bin',
		)
	endforeach
endif

edid_decode_sources = [
	'calc-gtf-cvt.cpp',
	'calc-ovt.cpp',
	'edid-decode.cpp',
	'parse-base-block.cpp',
	'parse-cta-block.cpp',
	'parse-di-ext-block.cpp',
	'parse-displayid-block.cpp',
	'parse-ls-ext-block.cpp',
	'parse-vtb-ext-block.cpp',
]

edid_decode = executable(
	'edid-decode',
	sources: edid_decode_sources,
	cpp_args: edid_decode_args,
	link_args: edid_decode_link_args,
	install: true,
)

meson.override_find_program(
	'edid-decode',
	edid_decode,
)

install_man('edid-decode.1')
