import 'package:flutter/widgets.dart';
import 'package:getx_helper/getx_helper.dart';
import 'package:silo_app/page/library/logic/library_logic.dart';

typedef LibraryLogicPutMixin<W extends StatefulWidget>
    = GetxLogicPutStateMixin<LibraryLogic, W>;

typedef LibraryLogicConsumerMixin<W extends StatefulWidget>
    = GetxLogicConsumerStateMixin<LibraryLogic, W>;

/// Sections that rebuild independently.
///
/// Progress ticks several times a second, and rebuilding the stored-model list
/// and the variant table at that rate would be wasted work — so each section
/// listens for its own update only.
enum LibraryUpdateType {
  search,
  variants,
  download,
  stored,
  targets,
}

/// Where a run currently is, for the status line.
enum LibraryStatus {
  idle,
  resolving,
  downloading,

  /// Every byte has landed and the SHA-256 is being computed. On a 27 GB model
  /// this takes long enough that saying nothing looks like a hang.
  verifying,

  paused,
  cancelled,
  done,
  failed,
}
