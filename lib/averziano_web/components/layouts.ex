defmodule AverzianoWeb.Layouts do
  use AverzianoWeb, :html

  import AverzianoWeb.AdminComponents, only: [nav_link: 1, avatar: 1]

  embed_templates "layouts/*"
end
