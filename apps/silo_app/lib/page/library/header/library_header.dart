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
  queue,
  stored,
  targets,
}
