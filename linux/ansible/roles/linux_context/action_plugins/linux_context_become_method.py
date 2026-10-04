"""Read the resolved become method without connecting or escalating privileges."""

from ansible.errors import AnsibleActionFail
from ansible.plugins.action import ActionBase


class ActionModule(ActionBase):
    TRANSFERS_FILES = False
    _requires_connection = False

    def run(self, tmp=None, task_vars=None):
        result = super().run(tmp, task_vars)
        if self._task.args:
            raise AnsibleActionFail('This action does not accept arguments.')

        # Ansible has already applied CLI, inherited keywords, and connection
        # variables here. A config lookup alone misses CLI and play overrides.
        result.update(changed=False, become_method=self._play_context.become_method)
        return result
