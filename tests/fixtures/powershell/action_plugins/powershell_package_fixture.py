"""Record simulated package operations; never invoke host package managers."""
import json
import os
from ansible.plugins.action import ActionBase

class ActionModule(ActionBase):
    def run(self, tmp=None, task_vars=None):
        args = self._task.args
        with open(os.environ['PS_FIXTURE_LOG'], 'a', encoding='utf-8') as stream:
            stream.write(json.dumps(args) + '\n')
        operation = args['operation']
        if operation == 'command':
            return {'changed': False, 'rc': 0, 'stdout': os.environ.get('PS_FIXTURE_SOURCE', 'False')}
        if operation == 'stat':
            return {'changed': False, 'stat': {'exists': True}}
        if operation == 'apt' and args['arguments'].get('name') == 'powershell':
            if os.environ.get('PS_FIXTURE_FAILURE'):
                return {'failed': True, 'msg': 'fixture: package hold or repository failure'}
            return {'changed': os.environ.get('PS_FIXTURE_CURRENT') != '1'}
        return {'changed': False}
