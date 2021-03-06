// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:core';

import 'package:analysis_server/protocol/protocol_constants.dart';
import 'package:analysis_server/src/analysis_server.dart';
import 'package:analysis_server/src/computer/computer_hover.dart';
import 'package:analysis_server/src/computer/computer_signature.dart';
import 'package:analysis_server/src/computer/imported_elements_computer.dart';
import 'package:analysis_server/src/domain_abstract.dart';
import 'package:analysis_server/src/domains/analysis/navigation_dart.dart';
import 'package:analysis_server/src/plugin/plugin_manager.dart';
import 'package:analysis_server/src/plugin/request_converter.dart';
import 'package:analysis_server/src/plugin/result_merger.dart';
import 'package:analysis_server/src/protocol/protocol_internal.dart';
import 'package:analysis_server/src/protocol_server.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' as engine;
import 'package:analyzer/src/dart/analysis/driver.dart';
import 'package:analyzer/src/dartdoc/dartdoc_directive_info.dart';
import 'package:analyzer/src/generated/engine.dart' as engine;
import 'package:analyzer_plugin/protocol/protocol.dart' as plugin;
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/protocol/protocol_constants.dart' as plugin;
import 'package:analyzer_plugin/protocol/protocol_generated.dart' as plugin;
import 'package:analyzer_plugin/src/utilities/navigation/navigation.dart';

// TODO(devoncarew): See #31456 for the tracking issue to remove this flag.
final bool disableManageImportsOnPaste = true;

/**
 * Instances of the class [AnalysisDomainHandler] implement a [RequestHandler]
 * that handles requests in the `analysis` domain.
 */
class AnalysisDomainHandler extends AbstractRequestHandler {
  /**
   * Initialize a newly created handler to handle requests for the given [server].
   */
  AnalysisDomainHandler(AnalysisServer server) : super(server);

  /**
   * Implement the `analysis.getErrors` request.
   */
  Future<void> getErrors(Request request) async {
    String file = new AnalysisGetErrorsParams.fromRequest(request).file;

    if (server.sendResponseErrorIfInvalidFilePath(request, file)) {
      return;
    }

    ResolvedUnitResult result = await server.getResolvedUnit(file);

    if (result?.state != ResultState.VALID) {
      server.sendResponse(new Response.getErrorsInvalidFile(request));
      return;
    }

    List<AnalysisError> protocolErrors = doAnalysisError_listFromEngine(
      result.session.analysisContext.analysisOptions,
      result.lineInfo,
      result.errors,
    );
    server.sendResponse(
        new AnalysisGetErrorsResult(protocolErrors).toResponse(request.id));
  }

  /**
   * Implement the `analysis.getHover` request.
   */
  Future<void> getHover(Request request) async {
    // TODO(brianwilkerson) Determine whether this await is necessary.
    await null;
    var params = new AnalysisGetHoverParams.fromRequest(request);
    var file = params.file;

    if (server.sendResponseErrorIfInvalidFilePath(request, file)) {
      return;
    }

    // Prepare the resolved units.
    ResolvedUnitResult result = await server.getResolvedUnit(file);
    CompilationUnit unit = result?.unit;

    // Prepare the hovers.
    List<HoverInformation> hovers = <HoverInformation>[];
    if (unit != null) {
      HoverInformation hoverInformation = new DartUnitHoverComputer(
              _getDartdocDirectiveInfoFor(result), unit, params.offset)
          .compute();
      if (hoverInformation != null) {
        hovers.add(hoverInformation);
      }
    }

    // Send the response.
    server.sendResponse(
        new AnalysisGetHoverResult(hovers).toResponse(request.id));
  }

  /**
   * Implement the `analysis.getImportedElements` request.
   */
  Future<void> getImportedElements(Request request) async {
    // TODO(brianwilkerson) Determine whether this await is necessary.
    await null;
    var params = new AnalysisGetImportedElementsParams.fromRequest(request);
    var file = params.file;

    if (server.sendResponseErrorIfInvalidFilePath(request, file)) {
      return;
    }

    //
    // Prepare the resolved unit.
    //
    ResolvedUnitResult result = await server.getResolvedUnit(file);
    if (result?.state != ResultState.VALID) {
      server.sendResponse(new Response.getImportedElementsInvalidFile(request));
      return;
    }

    List<ImportedElements> elements;

    //
    // Compute the list of imported elements.
    //
    if (disableManageImportsOnPaste) {
      elements = <ImportedElements>[];
    } else {
      elements = new ImportedElementsComputer(
              result.unit, params.offset, params.length)
          .compute();
    }

    //
    // Send the response.
    //
    server.sendResponse(
        new AnalysisGetImportedElementsResult(elements).toResponse(request.id));
  }

  /**
   * Implement the `analysis.getLibraryDependencies` request.
   */
  Response getLibraryDependencies(Request request) {
    return new Response.unsupportedFeature(request.id,
        'Please contact the Dart analyzer team if you need this request.');
//    server.onAnalysisComplete.then((_) {
//      LibraryDependencyCollector collector =
//          new LibraryDependencyCollector(server.analysisContexts);
//      Set<String> libraries = collector.collectLibraryDependencies();
//      Map<String, Map<String, List<String>>> packageMap =
//          collector.calculatePackageMap(server.folderMap);
//      server.sendResponse(new AnalysisGetLibraryDependenciesResult(
//              libraries.toList(growable: false), packageMap)
//          .toResponse(request.id));
//    }).catchError((error, st) {
//      server.sendResponse(new Response.serverError(request, error, st));
//    });
//    // delay response
//    return Response.DELAYED_RESPONSE;
  }

  /**
   * Implement the `analysis.getNavigation` request.
   */
  Future<void> getNavigation(Request request) async {
    // TODO(brianwilkerson) Determine whether this await is necessary.
    await null;
    var params = new AnalysisGetNavigationParams.fromRequest(request);
    String file = params.file;
    int offset = params.offset;
    int length = params.length;

    if (server.sendResponseErrorIfInvalidFilePath(request, file)) {
      return;
    }

    AnalysisDriver driver = server.getAnalysisDriver(file);
    if (driver == null) {
      server.sendResponse(new Response.getNavigationInvalidFile(request));
    } else {
      //
      // Allow plugins to start computing navigation data.
      //
      plugin.AnalysisGetNavigationParams requestParams =
          new plugin.AnalysisGetNavigationParams(file, offset, length);
      Map<PluginInfo, Future<plugin.Response>> pluginFutures = server
          .pluginManager
          .broadcastRequest(requestParams, contextRoot: driver.contextRoot);
      //
      // Compute navigation data generated by server.
      //
      List<AnalysisNavigationParams> allResults = <AnalysisNavigationParams>[];
      ResolvedUnitResult result = await server.getResolvedUnit(file);
      if (result?.state == ResultState.VALID) {
        CompilationUnit unit = result?.unit;
        NavigationCollectorImpl collector = new NavigationCollectorImpl();
        computeDartNavigation(
            server.resourceProvider, collector, unit, offset, length);
        collector.createRegions();
        allResults.add(new AnalysisNavigationParams(
            file, collector.regions, collector.targets, collector.files));
      }
      //
      // Add the navigation data produced by plugins to the server-generated
      // navigation data.
      //
      if (pluginFutures != null) {
        List<plugin.Response> responses = await waitForResponses(pluginFutures,
            requestParameters: requestParams);
        for (plugin.Response response in responses) {
          plugin.AnalysisGetNavigationResult result =
              new plugin.AnalysisGetNavigationResult.fromResponse(response);
          allResults.add(new AnalysisNavigationParams(
              file, result.regions, result.targets, result.files));
        }
      }
      //
      // Return the result.
      //
      ResultMerger merger = new ResultMerger();
      AnalysisNavigationParams mergedResults =
          merger.mergeNavigation(allResults);
      if (mergedResults == null) {
        server.sendResponse(new AnalysisGetNavigationResult(
                <String>[], <NavigationTarget>[], <NavigationRegion>[])
            .toResponse(request.id));
      } else {
        server.sendResponse(new AnalysisGetNavigationResult(mergedResults.files,
                mergedResults.targets, mergedResults.regions)
            .toResponse(request.id));
      }
    }
  }

  /**
   * Implement the `analysis.getReachableSources` request.
   */
  Response getReachableSources(Request request) {
    return new Response.unsupportedFeature(request.id,
        'Please contact the Dart analyzer team if you need this request.');
//    AnalysisGetReachableSourcesParams params =
//        new AnalysisGetReachableSourcesParams.fromRequest(request);
//    ContextSourcePair pair = server.getContextSourcePair(params.file);
//    if (pair.context == null || pair.source == null) {
//      return new Response.getReachableSourcesInvalidFile(request);
//    }
//    Map<String, List<String>> sources =
//        new ReachableSourceCollector(pair.source, pair.context)
//            .collectSources();
//    return new AnalysisGetReachableSourcesResult(sources)
//        .toResponse(request.id);
  }

  /**
   * Implement the `analysis.getSignature` request.
   */
  Future<void> getSignature(Request request) async {
    var params = new AnalysisGetSignatureParams.fromRequest(request);
    var file = params.file;

    if (server.sendResponseErrorIfInvalidFilePath(request, file)) {
      return;
    }

    // Prepare the resolved units.
    ResolvedUnitResult result = await server.getResolvedUnit(file);

    if (result?.state != ResultState.VALID) {
      server.sendResponse(new Response.getSignatureInvalidFile(request));
      return;
    }

    // Ensure the offset provided is a valid location in the file.
    final unit = result.unit;
    final computer = new DartUnitSignatureComputer(
        _getDartdocDirectiveInfoFor(result), unit, params.offset);
    if (!computer.offsetIsValid) {
      server.sendResponse(new Response.getSignatureInvalidOffset(request));
      return;
    }

    // Try to get a signature.
    final signature = computer.compute();
    if (signature == null) {
      server.sendResponse(new Response.getSignatureUnknownFunction(request));
      return;
    }

    server.sendResponse(signature.toResponse(request.id));
  }

  @override
  Response handleRequest(Request request) {
    try {
      String requestName = request.method;
      if (requestName == ANALYSIS_REQUEST_GET_ERRORS) {
        getErrors(request);
        return Response.DELAYED_RESPONSE;
      } else if (requestName == ANALYSIS_REQUEST_GET_HOVER) {
        getHover(request);
        return Response.DELAYED_RESPONSE;
      } else if (requestName == ANALYSIS_REQUEST_GET_IMPORTED_ELEMENTS) {
        getImportedElements(request);
        return Response.DELAYED_RESPONSE;
      } else if (requestName == ANALYSIS_REQUEST_GET_LIBRARY_DEPENDENCIES) {
        return getLibraryDependencies(request);
      } else if (requestName == ANALYSIS_REQUEST_GET_NAVIGATION) {
        getNavigation(request);
        return Response.DELAYED_RESPONSE;
      } else if (requestName == ANALYSIS_REQUEST_GET_REACHABLE_SOURCES) {
        return getReachableSources(request);
      } else if (requestName == ANALYSIS_REQUEST_GET_SIGNATURE) {
        getSignature(request);
        return Response.DELAYED_RESPONSE;
      } else if (requestName == ANALYSIS_REQUEST_REANALYZE) {
        return reanalyze(request);
      } else if (requestName == ANALYSIS_REQUEST_SET_ANALYSIS_ROOTS) {
        return setAnalysisRoots(request);
      } else if (requestName == ANALYSIS_REQUEST_SET_GENERAL_SUBSCRIPTIONS) {
        return setGeneralSubscriptions(request);
      } else if (requestName == ANALYSIS_REQUEST_SET_PRIORITY_FILES) {
        return setPriorityFiles(request);
      } else if (requestName == ANALYSIS_REQUEST_SET_SUBSCRIPTIONS) {
        return setSubscriptions(request);
      } else if (requestName == ANALYSIS_REQUEST_UPDATE_CONTENT) {
        return updateContent(request);
      } else if (requestName == ANALYSIS_REQUEST_UPDATE_OPTIONS) {
        return updateOptions(request);
      }
    } on RequestFailure catch (exception) {
      return exception.response;
    }
    return null;
  }

  /**
   * Implement the 'analysis.reanalyze' request.
   */
  Response reanalyze(Request request) {
    server.options.analytics?.sendEvent('analysis', 'reanalyze');

    server.reanalyze();

    //
    // Restart all of the plugins. This is an async operation that will happen
    // in the background.
    //
    server.pluginManager.restartPlugins();
    //
    // Send the response.
    //
    return new AnalysisReanalyzeResult().toResponse(request.id);
  }

  /**
   * Implement the 'analysis.setAnalysisRoots' request.
   */
  Response setAnalysisRoots(Request request) {
    var params = new AnalysisSetAnalysisRootsParams.fromRequest(request);
    List<String> includedPathList = params.included;
    List<String> excludedPathList = params.excluded;

    server.options.analytics?.sendEvent('analysis', 'setAnalysisRoots',
        value: includedPathList.length);

    // validate
    for (String path in includedPathList) {
      if (!server.isValidFilePath(path)) {
        return new Response.invalidFilePathFormat(request, path);
      }
    }
    for (String path in excludedPathList) {
      if (!server.isValidFilePath(path)) {
        return new Response.invalidFilePathFormat(request, path);
      }
    }
    Map<String, String> packageRoots =
        params.packageRoots ?? <String, String>{};

    if (server.detachableFileSystemManager != null) {
      server.detachableFileSystemManager.setAnalysisRoots(
          request.id, includedPathList, excludedPathList, packageRoots);
    } else {
      server.setAnalysisRoots(
          request.id, includedPathList, excludedPathList, packageRoots);
    }
    return new AnalysisSetAnalysisRootsResult().toResponse(request.id);
  }

  /**
   * Implement the 'analysis.setGeneralSubscriptions' request.
   */
  Response setGeneralSubscriptions(Request request) {
    AnalysisSetGeneralSubscriptionsParams params =
        new AnalysisSetGeneralSubscriptionsParams.fromRequest(request);
    server.setGeneralAnalysisSubscriptions(params.subscriptions);
    return new AnalysisSetGeneralSubscriptionsResult().toResponse(request.id);
  }

  /**
   * Implement the 'analysis.setPriorityFiles' request.
   */
  Response setPriorityFiles(Request request) {
    var params = new AnalysisSetPriorityFilesParams.fromRequest(request);

    for (var file in params.files) {
      if (!server.isAbsoluteAndNormalized(file)) {
        return Response.invalidFilePathFormat(request, file);
      }
    }

    server.setPriorityFiles(request.id, params.files);
    //
    // Forward the request to the plugins.
    //
    RequestConverter converter = new RequestConverter();
    server.pluginManager.setAnalysisSetPriorityFilesParams(
        converter.convertAnalysisSetPriorityFilesParams(params));
    //
    // Send the response.
    //
    return new AnalysisSetPriorityFilesResult().toResponse(request.id);
  }

  /**
   * Implement the 'analysis.setSubscriptions' request.
   */
  Response setSubscriptions(Request request) {
    var params = new AnalysisSetSubscriptionsParams.fromRequest(request);

    for (var fileList in params.subscriptions.values) {
      for (var file in fileList) {
        if (!server.isAbsoluteAndNormalized(file)) {
          return Response.invalidFilePathFormat(request, file);
        }
      }
    }

    // parse subscriptions
    Map<AnalysisService, Set<String>> subMap = mapMap(params.subscriptions,
        valueCallback: (List<String> subscriptions) => subscriptions.toSet());
    server.setAnalysisSubscriptions(subMap);
    //
    // Forward the request to the plugins.
    //
    RequestConverter converter = new RequestConverter();
    server.pluginManager.setAnalysisSetSubscriptionsParams(
        converter.convertAnalysisSetSubscriptionsParams(params));
    //
    // Send the response.
    //
    return new AnalysisSetSubscriptionsResult().toResponse(request.id);
  }

  /**
   * Implement the 'analysis.updateContent' request.
   */
  Response updateContent(Request request) {
    var params = new AnalysisUpdateContentParams.fromRequest(request);

    for (var file in params.files.keys) {
      if (!server.isAbsoluteAndNormalized(file)) {
        return Response.invalidFilePathFormat(request, file);
      }
    }

    server.updateContent(request.id, params.files);
    //
    // Forward the request to the plugins.
    //
    RequestConverter converter = new RequestConverter();
    server.pluginManager.setAnalysisUpdateContentParams(
        converter.convertAnalysisUpdateContentParams(params));
    //
    // Send the response.
    //
    return new AnalysisUpdateContentResult().toResponse(request.id);
  }

  /**
   * Implement the 'analysis.updateOptions' request.
   */
  Response updateOptions(Request request) {
    // options
    var params = new AnalysisUpdateOptionsParams.fromRequest(request);
    AnalysisOptions newOptions = params.options;
    List<OptionUpdater> updaters = new List<OptionUpdater>();
    if (newOptions.generateDart2jsHints != null) {
      updaters.add((engine.AnalysisOptionsImpl options) {
        options.dart2jsHint = newOptions.generateDart2jsHints;
      });
    }
    if (newOptions.generateHints != null) {
      updaters.add((engine.AnalysisOptionsImpl options) {
        options.hint = newOptions.generateHints;
      });
    }
    if (newOptions.generateLints != null) {
      updaters.add((engine.AnalysisOptionsImpl options) {
        options.lint = newOptions.generateLints;
      });
    }
    server.updateOptions(updaters);
    return new AnalysisUpdateOptionsResult().toResponse(request.id);
  }

  DartdocDirectiveInfo _getDartdocDirectiveInfoFor(ResolvedUnitResult result) {
    // TODO(brianwilkerson) Consider moving this to AnalysisServer.
    return server.declarationsTracker
            ?.getContext(result.session.analysisContext)
            ?.dartdocDirectiveInfo ??
        new DartdocDirectiveInfo();
  }
}
