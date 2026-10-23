/// The most paths a diagnostic lists: a payload that is wrong everywhere is not
/// worth more.
const int _maxReportedPaths = 10;

const String _pathSeparator = '.';
const String _pathsSeparator = ',';

/// What stands for the root of a payload, when the payload itself has the wrong
/// type.
const String rootPath = r'$';

/// Where a payload broke its schema, as `agenda.0.status,title`: the names of
/// the fields and the positions in the lists, never a value. Each issue is the
/// path to the flaw, a list of field names and positions; an empty path is the
/// payload as a whole. Sorted and without repeats, so that the same flaw gives
/// the same diagnostic.
String issuePathsOf(Iterable<List<Object>> issues) {
  final paths = {
    for (final issue in issues)
      if (issue.isEmpty)
        rootPath
      else
        issue.map((step) => '$step').join(_pathSeparator),
  }.toList()..sort();
  return paths.take(_maxReportedPaths).join(_pathsSeparator);
}
