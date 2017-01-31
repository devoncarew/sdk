Checklist to ensure that we have integration test coverage of all analysis
server calls. This file is validated by `coverage_test.dart`.

## server domain
- [x] server.getVersion
- [x] server.shutdown
- [x] server.setSubscriptions

## analysis domain
- [x] analysis.getErrors
- [x] analysis.getHover
- [ ] analysis.getReachableSources
- [ ] analysis.getLibraryDependencies
- [ ] analysis.getNavigation
- [x] analysis.reanalyze
- [x] analysis.setAnalysisRoots
- [ ] analysis.setGeneralSubscriptions
- [x] analysis.setPriorityFiles
- [x] analysis.setSubscriptions
- [x] analysis.updateContent
- [ ] analysis.updateOptions

## completion domain
- [x] completion.getSuggestions

## search domain
- [ ] search.findElementReferences
- [ ] search.findMemberDeclarations
- [ ] search.findMemberReferences
- [ ] search.findTopLevelDeclarations
- [x] search.getTypeHierarchy

## edit domain
- [ ] edit.format
- [ ] edit.getAssists
- [ ] edit.getAvailableRefactorings
- [ ] edit.getFixes
- [ ] edit.getRefactoring
- [ ] edit.sortMembers
- [ ] edit.organizeDirectives

## execution domain
- [ ] execution.createContext
- [ ] execution.deleteContext
- [ ] execution.mapUri
- [ ] execution.setSubscriptions

## diagnostic domain
- [ ] diagnostic.getDiagnostics
