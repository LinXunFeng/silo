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
  results,
  variants,
  queue,
  stored,
  targets,

  /// The sidebar: which section is showing, and the counts beside each entry.
  ///
  /// Deliberately not fired on every progress tick — only when a count or the
  /// selection actually changes, so the nav stays still while bytes move.
  navigation,
}

/// The four things this window does, one at a time.
///
/// Everything used to be stacked in a single scrolling column, where a long
/// list of quantisations pushed the queue out of sight exactly when a download
/// was running. One section at a time means nothing competes for the fold.
enum LibrarySection {
  discover,
  library,
  queue,
  targets,
}
