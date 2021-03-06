'use strict';

angular.module('QuepidApp')
  .controller('ExportEntireCaseModalInstanceCtrl', [
    '$scope',
    '$uibModalInstance',
    'querySnapshotSvc',
    'theCase',
    function ($scope, $uibModalInstance, querySnapshotSvc, theCase) {
      var ctrl = this;

      ctrl.theCase = theCase;
      ctrl.snapshots  = querySnapshotSvc.snapshots;

      ctrl.options = {
        which: 'undefined',
        snapshot: 'undefined'
      };

      // Watches
      $scope.$watch('ctrl.options', function(newVal, oldVal) {
        if (newVal !== oldVal) {
          if (oldVal.selection !== newVal.selection) {
            ctrl.options.which = 'snapshot';
          }
        }
      },true);

      ctrl.ok = function () {
        $uibModalInstance.close(ctrl.options);
      };

      ctrl.cancel = function () {
        $uibModalInstance.dismiss('cancel');
      };
    }
  ]);
