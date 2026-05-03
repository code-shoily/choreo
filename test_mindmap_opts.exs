alias Choreo.MindMap

legend =
  MindMap.new()
  |> MindMap.set_root(:root, label: "Root")
  |> MindMap.add_topic(:topic, label: "Topic")
  |> MindMap.add_subtopic(:subtopic, label: "Subtopic")
  |> MindMap.add_note(:note, label: "Note")
  |> MindMap.branch(:root, :topic)
  |> MindMap.branch(:topic, :subtopic)
  |> MindMap.branch(:subtopic, :note)

dot = MindMap.to_dot(legend, theme: :default, rankdir: :lr)
IO.puts(String.contains?(dot, "rankdir=LR"))
