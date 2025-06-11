#
# This file is part of Astarte.
#
# Copyright 2025 SECO Mind Srl
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0
#

defmodule Astarte.DataUpdaterPlant.DataUpdater.Core.TriggerTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Astarte.DataUpdaterPlant.DataUpdater
  alias Astarte.DataUpdaterPlant.DataUpdater.Core.Trigger
  alias Astarte.DataUpdaterPlant.DataUpdater.State
  alias Astarte.Core.Generators.Device, as: DeviceGenerator
  alias Astarte.Core.Triggers.SimpleTriggersProtobuf.AMQPTriggerTarget
  alias Astarte.DataUpdaterPlant.AMQPTestHelper
  alias Astarte.DataUpdaterPlant.TriggersHandler

  use Astarte.Cases.Data, async: true
  use Astarte.Cases.Device
  use ExUnitProperties

  import Astarte.Helpers.DataUpdater

  @moduletag :data_updater

  setup_all :populate_interfaces

  setup_all %{realm_name: realm_name, device: device} do
    setup_data_updater(realm_name, device.encoded_id)
    state = DataUpdater.dump_state(realm_name, device.encoded_id)

    %{state: state}
  end

  defp mock_trigger_target do
    %AMQPTriggerTarget{
      parent_trigger_id: :uuid.get_v4(),
      simple_trigger_id: :uuid.get_v4(),
      static_headers: [],
      routing_key: AMQPTestHelper.events_routing_key()
    }
  end

  defp mock_device_trigger(state, event_type) do
    %{state | device_triggers: %{event_type => [mock_trigger_target()]}}
  end

  describe "execute_pre_change_triggers/9" do
    test "executes triggers for pre-change events with empty triggers", context do
      triggers = {[], [], [], []}

      %{
        state: state
      } = context

      Mimic.reject(&TriggersHandler.value_change/8)

      assert :ok ==
               Trigger.execute_pre_change_triggers(
                 triggers,
                 state.realm,
                 state.device_id,
                 "test.interface",
                 "/test/path",
                 "old_value",
                 "new_value",
                 1_600_000_000,
                 %{}
               )
    end

    test "execute_pre_change_triggers/9 executes triggers when value changes" do
      triggers = {[%{trigger_targets: [mock_trigger_target()]}], [], [], []}
      realm = "test_realm"
      device = "test_device"
      interface = "test_interface"
      path = "/test/path"
      previous_value = nil
      value = 42
      timestamp = DateTime.utc_now()
      trigger_id_to_policy_name_map = %{1 => "test_policy"}

      Mimic.expect(TriggersHandler, :value_change, fn _target_with_policy_list,
                                                      ^realm,
                                                      device,
                                                      interface,
                                                      path,
                                                      _old_bson_value,
                                                      _payload,
                                                      ^timestamp ->
        assert device == "test_device"
        assert interface == "test_interface"
        assert path == "/test/path"
        :ok
      end)

      assert :ok =
               Trigger.execute_pre_change_triggers(
                 triggers,
                 realm,
                 device,
                 interface,
                 path,
                 previous_value,
                 value,
                 timestamp,
                 trigger_id_to_policy_name_map
               )
    end

    test "does not execute triggers when value remains the same", context do
      trigger_target = mock_trigger_target()
      triggers = {[%{trigger_targets: [trigger_target]}], [], [], []}

      %{
        state: state
      } = context

      Mimic.reject(&TriggersHandler.value_change/8)

      assert :ok ==
               Trigger.execute_pre_change_triggers(
                 triggers,
                 state.realm,
                 state.device_id,
                 "test.interface",
                 "/test/path",
                 "same_value",
                 "same_value",
                 1_600_000_000,
                 %{1 => "test_policy"}
               )
    end
  end

  describe "execute_post_change_triggers/9" do
    test "executes triggers for post-change events with empty triggers", context do
      triggers = {[], [], [], []}

      %{
        state: state
      } = context

      Mimic.reject(&TriggersHandler.path_created/7)
      Mimic.reject(&TriggersHandler.path_removed/6)
      Mimic.reject(&TriggersHandler.value_change_applied/8)

      assert :ok ==
               Trigger.execute_post_change_triggers(
                 triggers,
                 state.realm,
                 state.device_id,
                 "test.interface",
                 "/test/path",
                 "old_value",
                 "new_value",
                 1_600_000_000,
                 %{}
               )
    end

    test "execute_post_change_triggers/9 executes path_created triggers when value changes from nil" do
      triggers = {[], [], [%{trigger_targets: [mock_trigger_target()]}], []}
      realm = "test_realm"
      device = "test_device"
      interface = "test_interface"
      path = "/test/path"
      previous_value = nil
      value = 42
      timestamp = DateTime.utc_now()
      trigger_id_to_policy_name_map = %{1 => "test_policy"}

      Mimic.expect(TriggersHandler, :path_created, fn _target_with_policy_list,
                                                      ^realm,
                                                      device,
                                                      interface,
                                                      path,
                                                      _payload,
                                                      ^timestamp ->
        assert device == "test_device"
        assert interface == "test_interface"
        assert path == "/test/path"
        :ok
      end)

      assert :ok =
               Trigger.execute_post_change_triggers(
                 triggers,
                 realm,
                 device,
                 interface,
                 path,
                 previous_value,
                 value,
                 timestamp,
                 trigger_id_to_policy_name_map
               )
    end

    test "execute_post_change_triggers/9 executes path_removed triggers when value changes to nil" do
      triggers = {[], [], [], [%{trigger_targets: [mock_trigger_target()]}]}
      realm = "test_realm"
      device = "test_device"
      interface = "test_interface"
      path = "/test/path"
      previous_value = 42
      value = nil
      timestamp = DateTime.utc_now()
      trigger_id_to_policy_name_map = %{1 => "test_policy"}

      Mimic.expect(TriggersHandler, :path_removed, fn _target_with_policy_list,
                                                      ^realm,
                                                      device,
                                                      interface,
                                                      path,
                                                      ^timestamp ->
        assert device == "test_device"
        assert interface == "test_interface"
        assert path == "/test/path"
        :ok
      end)

      assert :ok =
               Trigger.execute_post_change_triggers(
                 triggers,
                 realm,
                 device,
                 interface,
                 path,
                 previous_value,
                 value,
                 timestamp,
                 trigger_id_to_policy_name_map
               )
    end

    test "execute_post_change_triggers/9 executes value_change_applied triggers when value changes" do
      triggers = {[], [%{trigger_targets: [mock_trigger_target()]}], [], []}
      realm = "test_realm"
      device = "test_device"
      interface = "test_interface"
      path = "/test/path"
      previous_value = 42
      value = 43
      timestamp = DateTime.utc_now()
      trigger_id_to_policy_name_map = %{1 => "test_policy"}

      Mimic.expect(TriggersHandler, :value_change_applied, fn _target_with_policy_list,
                                                              ^realm,
                                                              device,
                                                              interface,
                                                              path,
                                                              _old_bson_value,
                                                              _payload,
                                                              ^timestamp ->
        assert device == "test_device"
        assert interface == "test_interface"
        assert path == "/test/path"
        :ok
      end)

      assert :ok =
               Trigger.execute_post_change_triggers(
                 triggers,
                 realm,
                 device,
                 interface,
                 path,
                 previous_value,
                 value,
                 timestamp,
                 trigger_id_to_policy_name_map
               )
    end
  end

  describe "execute_device_error_triggers/4" do
    test "executes triggers for device error events with empty triggers", context do
      %{
        state: state,
        realm_name: realm,
        device: device
      } = context

      device_id = device.encoded_id
      error_name = "test_error"
      error_metadata = %{"details" => "test details"}
      timestamp = 1_600_000_000_000_000
      timestamp_ms = 1_600_000_000_00

      Mimic.expect(TriggersHandler, :device_error, fn targets,
                                                      ^realm,
                                                      ^device_id,
                                                      ^error_name,
                                                      ^error_metadata,
                                                      ^timestamp_ms ->
        assert Enum.empty?(targets)

        :ok
      end)

      assert :ok ==
               Trigger.execute_device_error_triggers(
                 state,
                 error_name,
                 error_metadata,
                 timestamp
               )
    end

    test "execute_device_error_triggers/4 executes triggers for device error events with configured triggers",
         context do
      %{
        state: state,
        realm_name: realm,
        device: device
      } = context

      state = mock_device_trigger(state, :on_device_error)

      device_id = device.encoded_id
      error_name = "test_error"
      error_metadata = %{"details" => "test details"}
      timestamp = 1_600_000_000_000_000
      timestamp_ms = 1_600_000_000_00

      Mimic.expect(TriggersHandler, :device_error, fn targets,
                                                      ^realm,
                                                      ^device_id,
                                                      ^error_name,
                                                      ^error_metadata,
                                                      ^timestamp_ms ->
        refute Enum.empty?(targets)
        :ok
      end)

      assert :ok =
               Trigger.execute_device_error_triggers(
                 state,
                 error_name,
                 error_metadata,
                 timestamp
               )
    end

    test "execute_device_error_triggers/4 handles device error with empty metadata", context do
      %{
        state: state,
        realm_name: realm,
        device: device
      } = context

      state = mock_device_trigger(state, :on_device_error)

      device_id = device.encoded_id
      error_name = "test_error"
      error_metadata = %{}
      timestamp = 1_600_000_000_000_000
      timestamp_ms = 1_600_000_000_00

      Mimic.expect(TriggersHandler, :device_error, fn _target_with_policy_list,
                                                      ^realm,
                                                      ^device_id,
                                                      ^error_name,
                                                      ^error_metadata,
                                                      ^timestamp_ms ->
        :ok
      end)

      assert :ok =
               Trigger.execute_device_error_triggers(
                 state,
                 error_name,
                 error_metadata,
                 timestamp
               )
    end

    property "does not crash for random error names and metadata" do
      check all error_name <- string(:alphanumeric),
                error_metadata <- map_of(string(:alphanumeric), string(:alphanumeric)),
                timestamp <- integer(1_600_000_000_000_000..2_000_000_000_000_000),
                device_id <- DeviceGenerator.id() do
        state = %State{
          realm: "test_realm",
          device_id: device_id,
          device_triggers: %{},
          data_triggers: %{},
          trigger_id_to_policy_name: %{}
        }

        assert :ok ==
                 Trigger.execute_device_error_triggers(
                   state,
                   error_name,
                   error_metadata,
                   timestamp
                 )
      end
    end
  end
end
