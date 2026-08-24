// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Silo';

  @override
  String get tagline => '只下一份，处处可用。';

  @override
  String get searchLabel => '模型';

  @override
  String get searchPlaceholder => '关键词、author/repo，或模型页链接';

  @override
  String get searchAction => '查找';

  @override
  String get searching => '正在查找可用源…';

  @override
  String availableFrom(String sources) {
    return '可用源：$sources';
  }

  @override
  String get variantsTitle => '可选版本';

  @override
  String variantShards(int count) {
    return '$count 个分片';
  }

  @override
  String variantProjector(int count) {
    return '+$count 个 mmproj';
  }

  @override
  String variantSupportFiles(int count) {
    return '+$count 个配套文件';
  }

  @override
  String get pauseAction => '暂停';

  @override
  String get resumeAction => '继续';

  @override
  String get cancelAction => '取消';

  @override
  String get linkAction => '分发';

  @override
  String get removeAction => '移除';

  @override
  String get reclaimAction => '回收空间';

  @override
  String get refreshAction => '刷新';

  @override
  String get revealAction => '在访达中显示';

  @override
  String downloadFile(String name, int index, int count) {
    return '$name（第 $index / $count 个）';
  }

  @override
  String downloadStats(String received, String total, String rate, String eta) {
    return '$received / $total · $rate · 剩余 $eta';
  }

  @override
  String downloadConnections(int active, int done, int total) {
    return '$active 个连接 · $done/$total 分片';
  }

  @override
  String get statusResolving => '正在解析下载源…';

  @override
  String get statusVerifying => '正在校验 sha256…';

  @override
  String get statusPaused => '已暂停 —— 继续时会从断点接上';

  @override
  String get statusCancelled => '已取消';

  @override
  String statusDone(String name) {
    return '已入库：$name';
  }

  @override
  String get unknownValue => '—';

  @override
  String get libraryTitle => '模型库';

  @override
  String get libraryEmpty => '库里还是空的。';

  @override
  String librarySummary(int models, String size) {
    return '$models 个模型 · 占用 $size';
  }

  @override
  String librarySaved(String size) {
    return '去重省下 $size';
  }

  @override
  String entryLinkedTo(String targets) {
    return '已分发到 $targets';
  }

  @override
  String get entryNotLinked => '尚未分发';

  @override
  String entrySource(String source, String revision) {
    return '$source · $revision';
  }

  @override
  String get targetsTitle => '分发到';

  @override
  String get targetNotInstalled => '未安装';

  @override
  String linkedResult(String visible, String cost) {
    return '工具看到 $visible，实际额外占用 $cost';
  }

  @override
  String reclaimedSpace(String size, int count) {
    return '已释放 $size，共 $count 个 blob';
  }

  @override
  String get reclaimNothing => '没有可回收的内容';

  @override
  String sourceSpeed(String source, String rate) {
    return '$source：$rate';
  }

  @override
  String sourceUnavailable(String source) {
    return '$source：不可用';
  }

  @override
  String get queueTitle => '下载队列';

  @override
  String get queueEmpty => '队列是空的。';

  @override
  String get queueAddAction => '加入队列';

  @override
  String queueSummary(int pending) {
    return '$pending 个待下载';
  }

  @override
  String get queuePauseAllAction => '暂停队列';

  @override
  String get queueResumeAllAction => '开始队列';

  @override
  String get queueClearAction => '清理已完成';

  @override
  String get queueHeldNotice => '队列已暂停 —— 在你点开始之前不会有任何任务启动。';

  @override
  String queueRestoredNotice(int count) {
    return '从上次会话恢复了 $count 个任务，均为暂停状态。';
  }

  @override
  String get jobStatusQueued => '排队中';

  @override
  String get jobStatusRunning => '正在下载';

  @override
  String get jobStatusPaused => '已暂停';

  @override
  String get jobStatusCompleted => '已完成';

  @override
  String get jobStatusCancelled => '已取消';

  @override
  String get jobStatusFailed => '失败';

  @override
  String get moveUpAction => '上移';

  @override
  String get moveDownAction => '下移';

  @override
  String get removeFromQueueAction => '移出队列';

  @override
  String libraryReclaimable(String size) {
    return '$size 已无人引用 —— 回收即可释放';
  }

  @override
  String get unlinkAction => '取消分发';

  @override
  String gcResult(String freed, int count) {
    return '已释放 $freed，共 $count 个 blob';
  }

  @override
  String gcRetained(String size) {
    return '$size 未能释放 —— 仍安装在工具里';
  }

  @override
  String unlinkSkipped(int count) {
    return '$count 个文件未删除 —— 不是 Silo 放的那份';
  }

  @override
  String get searchResultsTitle => '搜索结果';

  @override
  String get searchNoResults => '没有匹配结果，换个关键词试试。';

  @override
  String get searchShowAll => '包含仅 transformers 格式的仓库';

  @override
  String resultDownloads(String count) {
    return '$count 次下载';
  }

  @override
  String resultOnSources(String sources) {
    return '来源：$sources';
  }

  @override
  String get reclaimTooltip => '删除库中已无人引用的文件';

  @override
  String get refreshTooltip => '重新读取模型库和工具目录';

  @override
  String reclaimConfirmTitle(String size) {
    return '回收 $size？';
  }

  @override
  String reclaimConfirmBody(int count) {
    return '有 $count 个文件已不被库中任何模型引用。已安装到工具里的模型不受影响。';
  }

  @override
  String get reclaimConfirmAction => '回收';

  @override
  String get confirmOkAction => '好';

  @override
  String get discoverTitle => '发现';

  @override
  String get discoverSubtitle => '一次搜遍所有镜像，也可以直接粘贴 author/repo。';

  @override
  String get discoverEmpty => '还没查找过任何模型';

  @override
  String get discoverEmptyHint => '试试关键词（比如 qwen3 coder），或者精确的 author/repo。';

  @override
  String get librarySubtitle => '只留一份实体文件，硬链接分发给每个要用它的工具。';

  @override
  String get libraryEmptyHint => '先查找一个模型试试。';

  @override
  String get queueSubtitle => '一次只跑一个 —— 同时下两个只是在瓜分同一条带宽。';

  @override
  String get queueEmptyHint => '先查找一个模型，把它加入队列。';

  @override
  String get targetsNavTitle => '分发目标';

  @override
  String get targetsSubtitle => '下载完成后硬链接到这些工具。';

  @override
  String targetsSelected(String targets) {
    return '将分发到 $targets';
  }

  @override
  String get targetsNoneSelected => '未选择分发目标 —— 下载完成后只会存入库中。';

  @override
  String get statModels => '模型';

  @override
  String get statOnDisk => '实际占用';

  @override
  String get statSaved => '去重节省';

  @override
  String get statReclaimable => '可回收';

  @override
  String get appearanceAction => '外观';

  @override
  String get appearanceTooltip => '跟随 macOS，或把窗口固定为某一种外观';

  @override
  String get appearanceSystem => '跟随系统';

  @override
  String get appearanceLight => '浅色';

  @override
  String get appearanceDark => '深色';
}
