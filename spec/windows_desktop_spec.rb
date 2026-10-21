require 'support/desktop_fixture'

RSpec.describe 'Windows desktop behavior', :windows, :live do
  include_context 'a native desktop fixture'

  it 'hands foreground between separate processes without modifying either draft' do
    other = Process.spawn({'BLINDLY4_FIXTURE_BACKGROUND' => '1'}, [fixture_binary, fixture_binary], '--test-app',
                          in: File::NULL, out: File::NULL, err: File::NULL)
    wait_for_observed_state('Second background fixture ready') do
      result = cli('find', '--pid', other, '--title', 'Fixture ready', '--role', 'AXStaticText')
      result.status == 0 && result.json.fetch('matches').any?
    end
    # Deliver input to the current foreground process before each fresh CLI
    # switches away, rather than relying on an expired foreground-lock timeout.
    app('key', '--key', 'escape')
    [other, @fixture_pid, other, @fixture_pid].each do |pid|
      result = cli('activate', '--pid', pid, '--profile')
      expect(result.status).to eq(0), result.stdout
      expect(result.json).to include('ok' => true, 'pid' => pid)
      expect(JSON.parse(result.stderr).fetch('activation')).to include('targetPid' => pid, 'activationAccepted' => true)
      expect(success('apps').fetch('apps')).to include(a_hash_including('pid' => pid, 'frontmost' => true))
      success('key', '--pid', pid, '--key', 'escape')
    end
    [other, @fixture_pid].each do |pid|
      fields = success('find', '--pid', pid, '--title', 'Draft', '--role', 'AXTextField').fetch('matches')
      expect(fields).to include(a_hash_including('title' => 'Draft', 'value' => ''))
      expect(success('find', '--pid', pid, '--title', 'Not submitted').fetch('matches')).not_to be_empty
    end
  ensure
    if other
      Process.kill('KILL', other)
      Process.waitpid(other)
    end
  end

  it 'reports matching native control types, roles, and supported actions' do
    [ ['Draft', 'AXTextField', 'Edit', []],
      ['Password', 'AXSecureTextField', 'Edit', []],
      ['Submit test draft', 'AXButton', 'Button', ['AXPress']],
      ['Test checkbox', 'AXCheckBox', 'CheckBox', ['AXPress']],
      ['Delivery choice', 'AXComboBox', 'ComboBox', ['AXShowMenu']],
      ['Scrollable options', 'AXList', 'List', []],
      ['Option 02', 'AXRow', 'ListItem', ['AXPress', 'AXScrollToVisible']],
      ['Fixture ready', 'AXStaticText', 'Text', []] ].each do |title, role, control_type, actions|
      path = find_control_path(title, role)
      row = app('inspect', '--path', path)
      expect(row).to include('role' => role, 'subrole' => "ControlType.#{control_type}")
      expect(row.fetch('actions')).to include(*actions) unless actions.empty?
      expect(app('actions', '--path', path)).to eq('path' => path, 'actions' => row.fetch('actions'))
    end
    expect_not_submitted
    app('press', '--path', submit, '--expect-description', 'Submit', '--require-value-path', draft, '--require-value', '')
    expect_label('Submission count: 1')
  end

  %w[ctrl+a command+a cmd+a].each do |shortcut|
    it "selects the matching draft with #{shortcut} and types Unicode through real keyboard input" do
      set_draft('original')
      app('focus', '--path', draft)
      expect(app('key', '--key', shortcut, '--target-path', draft, '--require-value', 'original')).to include('verified' => true)
      app('type', '--text', 'Typed Unicode: مرحبا café 🪟')
      expect(draft_value).to eq('Typed Unicode: مرحبا café 🪟')
      expect_not_submitted
    end
  end

  it 'preserves backward-delete and forward-delete keyboard behavior' do
    set_draft('abc')
    app('focus', '--path', draft)
    app('key', '--key', 'end')
    app('key', '--key', 'delete')
    expect(draft_value).to eq('ab')
    app('key', '--key', 'home')
    app('key', '--key', 'forward-delete')
    expect(draft_value).to eq('b')
  end

  it 'refuses input addressed to a process without a visible target window' do
    result = cli('key', '--pid', Process.pid, '--key', 'return')
    expect(result.status).to eq(77)
    expect(result.json.fetch('code')).to eq('accessibility_error')
    expect_not_submitted
  end
end
