"""Execute production tasks, replacing only host-mutating package/key boundaries."""
from ansible.plugins.strategy.linear import StrategyModule as LinearStrategy

class StrategyModule(LinearStrategy):
    def _queue_task(self, host, task, task_vars, play_context):
        action = task.action.rsplit('.', 1)[-1]
        fixture = action in {'apt', 'apt_repository', 'get_url', 'stat', 'file'}
        fixture |= action == 'command' and task.args.get('argv', [None])[0] != 'dpkg-query'
        if fixture:
            task = task.copy()
            task.args = {'operation': action, 'arguments': task.args}
            task.action = 'powershell_package_fixture'
            task.become = False
        return super()._queue_task(host, task, task_vars, play_context)
