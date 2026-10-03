defmodule Averziano.Accounts.Emails do
  @moduledoc "The emails sent to users: magic links and invitations."

  import Swoosh.Email

  @doc "A sign-in link."
  @spec magic_link(String.t(), String.t()) :: Swoosh.Email.t()
  def magic_link(to, url) do
    base(to, "Il tuo link per accedere a Work Baby")
    |> text_body("""
    Ciao,

    apri questo link per accedere a Work Baby:

    #{url}

    Il link vale 10 minuti e si può usare una sola volta. Se non l'hai richiesto tu, ignora questa email.
    """)
    |> html_body(
      layout("""
      <p>Ciao,</p>
      <p>premi il pulsante per accedere a Work Baby.</p>
      #{button(url, "Accedi")}
      <p style="color:#71717A;font-size:13px">Il link vale 10 minuti e si può usare una sola volta. Se non l'hai richiesto tu, ignora questa email.</p>
      """)
    )
  end

  @doc "The invitation a coach sends to a new client."
  @spec invitation(String.t(), String.t(), String.t(), String.t()) :: Swoosh.Email.t()
  def invitation(to, client_name, coach_name, url) do
    base(to, "#{coach_name} ti ha invitato su Work Baby")
    |> text_body("""
    Ciao #{client_name},

    #{coach_name} ti ha invitato su Work Baby, dove troverai i tuoi programmi di allenamento.

    Per accedere apri #{url} e inserisci questo indirizzo email: ti invieremo un link di accesso.
    """)
    |> html_body(
      layout("""
      <p>Ciao #{escape(client_name)},</p>
      <p>#{escape(coach_name)} ti ha invitato su Work Baby, dove troverai i tuoi programmi di allenamento.</p>
      #{button(url, "Accedi a Work Baby")}
      <p style="color:#71717A;font-size:13px">Inserisci questo indirizzo email e ti invieremo un link di accesso.</p>
      """)
    )
  end

  defp base(to, subject) do
    new()
    |> to(to)
    |> from(Application.fetch_env!(:averziano, :mail_from))
    |> subject(subject)
  end

  defp layout(content) do
    """
    <div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1E1E1E;font-size:15px;line-height:22px;max-width:480px;margin:0 auto;padding:24px">
      <p style="font-size:20px;font-weight:600;color:#5E30E6;margin:0 0 24px">Work Baby</p>
      #{content}
    </div>
    """
  end

  defp button(url, label) do
    ~s(<p style="margin:24px 0"><a href="#{escape(url)}" style="background:#5E30E6;color:#fff;text-decoration:none;font-weight:600;padding:12px 24px;border-radius:24px;display:inline-block">#{label}</a></p>)
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
