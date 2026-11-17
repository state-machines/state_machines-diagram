# Changelog

## [0.3.0](https://github.com/state-machines/state_machines-diagram/compare/state_machines-diagram/v0.2.1...state_machines-diagram/v0.3.0) (2026-11-17)


### Features

* build each part of a machine and draw what the core runs ([fb7aa1e](https://github.com/state-machines/state_machines-diagram/commit/fb7aa1eb5159e70d2e132f32c544a9c8f0589d5d))
* machine schema keeps branch order, callbacks and final states ([e977a68](https://github.com/state-machines/state_machines-diagram/commit/e977a68570e289c62589b1b027a7d034ebc78ef2))


### Bug Fixes

* a String condition goes through the core's own check first ([59da24b](https://github.com/state-machines/state_machines-diagram/commit/59da24b73daf77c0c15d56bba975f026fb680e09))
* a String condition the core always reads the same way is resolved ([9a1faac](https://github.com/state-machines/state_machines-diagram/commit/9a1faac62fafc79c794138fa43e89667b0536111))
* callbacks follow the order the core runs them ([72ea13c](https://github.com/state-machines/state_machines-diagram/commit/72ea13c97b6cd0c793b5ffc53abe08fbd906dcaa))
* check only the conditions the core evaluates, in its order ([ee04343](https://github.com/state-machines/state_machines-diagram/commit/ee043431f6ce3a89be214e72331093b4379fc8e7))
* draw only the transitions the core performs from each source ([56746b9](https://github.com/state-machines/state_machines-diagram/commit/56746b91a9f2ff896bf7013ffbb89fffbcc66835))
* machine schema the state-machines-rs validator accepts ([6c16002](https://github.com/state-machines/state_machines-diagram/commit/6c16002d6c87becc3312b091ad1ea4e5fa741398))
* read conditions as the core does and show callback conditions ([44eebba](https://github.com/state-machines/state_machines-diagram/commit/44eebba282595642e01a3fdcfc0e36c6a000b626))
* require state_machines 0.303.0 and use its public API ([a691331](https://github.com/state-machines/state_machines-diagram/commit/a6913318fcb01173302c3c3b9d4a2af6c47f9b14))
* requiring the gem leaves the global renderer alone ([77e1706](https://github.com/state-machines/state_machines-diagram/commit/77e1706c4a47805b6db52ba5d3625bd2c19ef3e7))
* run RuboCop in the default task and CI ([e7f4aa4](https://github.com/state-machines/state_machines-diagram/commit/e7f4aa44229b66f4cc3cdfa469878d12bb16c64d))
* the constant-condition test keeps RuboCop's method length ([152e6e1](https://github.com/state-machines/state_machines-diagram/commit/152e6e1aea3b6cc7183ad08cbb15c308c292b08b))
* the nil and :"" state test holds whether the core merges them or not ([98e7503](https://github.com/state-machines/state_machines-diagram/commit/98e7503be280afc0881113de1cae7ce497674756))

## [0.2.1](https://github.com/state-machines/state_machines-diagram/compare/state_machines-diagram-v0.2.0...state_machines-diagram/v0.2.1) (2026-11-17)


### Bug Fixes

* a diagram carries the state-based guards too ([9cbd012](https://github.com/state-machines/state_machines-diagram/commit/9cbd0120bfd4218880ae6042e794ab348e6d1e39))
* a loopback keeps each source state where it is ([54cc095](https://github.com/state-machines/state_machines-diagram/commit/54cc09549ac66fc885fa08b0bb40570eeb65b3fc))
* a nil human name or state name never reaches a label as nil ([b7ec8aa](https://github.com/state-machines/state_machines-diagram/commit/b7ec8aa4468a2500bc5a732c93b66bf9688b5377))
* a per-state diagram carries the transitions that touch the state ([da8c187](https://github.com/state-machines/state_machines-diagram/commit/da8c187a096353498b27429e2e9bb8f114638929))
* an excluded target is never drawn as the destination ([6372806](https://github.com/state-machines/state_machines-diagram/commit/637280618120cd5d7acb93adf6258807e74b7cf5))
* build diagrams through the diagram 0.4 keyword API ([b0a4225](https://github.com/state-machines/state_machines-diagram/commit/b0a42251a4eac974596e71148da1aa26c6fbbd49))
* draw every legal state name, guard group and terminal marker ([a4e9541](https://github.com/state-machines/state_machines-diagram/commit/a4e954160a20f33f6aaec7fd9460dc96ac7ebd90))
