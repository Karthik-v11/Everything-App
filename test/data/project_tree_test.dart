import 'package:everything_app/data/models/project.dart';
import 'package:everything_app/data/services/projects_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The project tree and the cascade a delete would take with it (Requirement 10).
///
/// The tree is rebuilt in memory from a flat list of rows on every read, so these
/// are the tests that stand between "sub-projects work" and a branch of the user's
/// projects silently detaching from the tree — still in the database, reachable from
/// no screen.
void main() {
  Project project(String id, {String? parent}) => Project(
        id: id,
        name: id,
        parentProjectId: parent,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  // a
  // ├── b
  // │   └── d
  // └── c
  // e
  final projects = [
    project('a'),
    project('b', parent: 'a'),
    project('c', parent: 'a'),
    project('d', parent: 'b'),
    project('e'),
  ];

  final tree = ProjectTree(projects);

  group('shape', () {
    test('roots are the projects with no parent', () {
      expect(tree.roots.map((p) => p.id), ['a', 'e']);
    });

    test('children are the direct sub-projects only', () {
      expect(tree.childrenOf('a').map((p) => p.id), ['b', 'c']);
      expect(tree.childrenOf('b').map((p) => p.id), ['d']);
      expect(tree.childrenOf('d'), isEmpty);
    });

    test('descendants reach every depth', () {
      // The cascade reads this. Missing `d` — a grandchild — would leave it in the
      // database pointing at a parent that no longer exists.
      expect(
        tree.descendantsOf('a').map((p) => p.id).toSet(),
        {'b', 'c', 'd'},
      );
    });

    test('ancestors are the breadcrumb, nearest parent first', () {
      expect(tree.ancestorsOf('d').map((p) => p.id), ['b', 'a']);
      expect(tree.ancestorsOf('a'), isEmpty);
    });
  });

  group('a cycle cannot hang the app', () {
    // Nothing in the app creates one. A bad restore or a future move could, and the
    // difference between "handled" and "not handled" here is the difference between
    // a wrong answer and an app that never draws another frame.
    final cyclic = ProjectTree([
      project('x', parent: 'y'),
      project('y', parent: 'x'),
    ]);

    test('descendants terminate', () {
      expect(cyclic.descendantsOf('x').map((p) => p.id), ['y']);
    });

    test('ancestors terminate', () {
      expect(cyclic.ancestorsOf('x').map((p) => p.id), ['y']);
    });
  });

  group('a project cannot be moved inside itself', () {
    test('not into itself', () {
      expect(tree.canReparent(project('a'), 'a'), isFalse);
    });

    test('not into its own child', () {
      expect(tree.canReparent(projects[0], 'b'), isFalse);
    });

    test('not into its own grandchild', () {
      // The case a one-level check would miss: moving `a` under `d` would take `a`,
      // `b`, `c` and `d` out of the tree in one move.
      expect(tree.canReparent(projects[0], 'd'), isFalse);
    });

    test('into an unrelated project, or to the top level', () {
      expect(tree.canReparent(projects[0], 'e'), isTrue);
      expect(tree.canReparent(projects[1], null), isTrue);
    });
  });

  group('the confirmation says what it will destroy', () {
    // Requirement 10.4 asks for a confirmation before deleting a project "and all its
    // contents". A dialog that said only "Delete project?" would be asking the user
    // to agree to something they had not been told.
    test('an empty project needs no warning', () {
      const contents = ProjectContents(
        projects: 0,
        tasks: 0,
        documents: 0,
        attachments: 0,
      );

      expect(contents.isEmpty, isTrue);
    });

    test('one of a kind is singular', () {
      const contents = ProjectContents(
        projects: 1,
        tasks: 1,
        documents: 0,
        attachments: 0,
      );

      expect(contents.summary, '1 sub-project and 1 task');
    });

    test('several kinds read as a sentence', () {
      const contents = ProjectContents(
        projects: 2,
        tasks: 11,
        documents: 3,
        attachments: 0,
      );

      expect(contents.summary, '2 sub-projects, 11 tasks and 3 documents');
    });

    test('a kind with nothing in it is not mentioned', () {
      const contents = ProjectContents(
        projects: 0,
        tasks: 4,
        documents: 0,
        attachments: 0,
      );

      expect(contents.summary, '4 tasks');
      expect(contents.isEmpty, isFalse);
    });
  });
}
