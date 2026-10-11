# Silo

A local model library: each model's bytes are kept once, and handed to every
tool that wants them.

## Language

**Store**:
The one place a model's bytes physically live, addressed by their digest.
_Avoid_: cache, repository

**Variant**:
A single choice within a hub repository — one quantisation, one
directory of a safetensors model, or one file picked on its own — and the
unit that is stored and linked. A file picked on its own is that file
alone, with nothing else from its folder.
_Avoid_: model file, quant

**Target**:
A local tool Silo hands models to, such as LM Studio or Draw Things.
_Avoid_: destination, app, backend

**Link**:
Placing a stored variant's files where a target looks for them, without a
second copy. The reverse is **unlink**. The Chinese interface calls it 分发.
_Avoid_: install, copy

**Default targets**:
The targets a new download is linked into once it finishes. A variant already
in the store is linked target by target instead.

**Import**:
A target's own step that turns linked files into a model it can run. Only
some targets need it; until it happens, a link there is a pick-list entry,
not a usable model.
_Avoid_: load, install
