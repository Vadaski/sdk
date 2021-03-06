// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/src/dart/analysis/experiments.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../dart/resolution/driver_resolution.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NotNullAwareNullSpreadTest);
  });
}

@reflectiveTest
class NotNullAwareNullSpreadTest extends DriverResolutionTest {
  @override
  AnalysisOptionsImpl get analysisOptions => AnalysisOptionsImpl()
    ..enabledExperiments = [
      EnableString.control_flow_collections,
      EnableString.spread_collections,
    ];

  test_listLiteral_notNullAware_nullLiteral() async {
    await assertErrorCodesInCode('''
var v = [...null];
''', [CompileTimeErrorCode.NOT_NULL_AWARE_NULL_SPREAD]);
  }

  test_listLiteral_notNullAware_nullTyped() async {
    await assertErrorCodesInCode('''
Null a = null;
var v = [...a];
''', [CompileTimeErrorCode.NOT_NULL_AWARE_NULL_SPREAD]);
  }

  test_listLiteral_nullAware_nullLiteral() async {
    await assertNoErrorsInCode('''
var v = [...?null];
''');
  }

  test_listLiteral_nullAware_nullTyped() async {
    await assertNoErrorsInCode('''
Null a = null;
var v = [...?a];
''');
  }

  test_mapLiteral_notNullAware_nullLiteral() async {
    await assertErrorCodesInCode('''
var v = <int, int>{...null};
''', [CompileTimeErrorCode.NOT_NULL_AWARE_NULL_SPREAD]);
  }

  test_mapLiteral_notNullAware_nullType() async {
    await assertErrorCodesInCode('''
Null a = null;
var v = <int, int>{...a};
''', [CompileTimeErrorCode.NOT_NULL_AWARE_NULL_SPREAD]);
  }

  test_mapLiteral_nullAware_nullLiteral() async {
    await assertNoErrorsInCode('''
var v = <int, int>{...?null};
''');
  }

  test_mapLiteral_nullAware_nullType() async {
    await assertNoErrorsInCode('''
Null a = null;
var v = <int, int>{...?a};
''');
  }

  test_setLiteral_notNullAware_nullLiteral() async {
    await assertErrorCodesInCode('''
var v = <int>{...null};
''', [CompileTimeErrorCode.NOT_NULL_AWARE_NULL_SPREAD]);
  }

  test_setLiteral_notNullAware_nullTyped() async {
    await assertErrorCodesInCode('''
Null a = null;
var v = <int>{...a};
''', [CompileTimeErrorCode.NOT_NULL_AWARE_NULL_SPREAD]);
  }

  test_setLiteral_nullAware_nullLiteral() async {
    await assertNoErrorsInCode('''
var v = <int>{...?null};
''');
  }

  test_setLiteral_nullAware_nullTyped() async {
    await assertNoErrorsInCode('''
Null a = null;
var v = <int>{...?a};
''');
  }
}
