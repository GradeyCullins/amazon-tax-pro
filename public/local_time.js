document.addEventListener("DOMContentLoaded", () => {
  const formatter = new Intl.DateTimeFormat(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZoneName: "short"
  });

  document.querySelectorAll("time[data-local-time]").forEach((element) => {
    const date = new Date(element.dateTime);
    if (!Number.isNaN(date.getTime())) element.textContent = formatter.format(date);
  });
});
